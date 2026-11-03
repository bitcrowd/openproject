# frozen_string_literal: true

#-- copyright
# OpenProject is an open source project management software.
# Copyright (C) the OpenProject GmbH
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License version 3.
#
# OpenProject is a fork of ChiliProject, which is a fork of Redmine. The copyright follows:
# Copyright (C) 2006-2013 Jean-Philippe Lang
# Copyright (C) 2010-2013 the ChiliProject Team
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <https://www.gnu.org/licenses/>.
#
# See COPYRIGHT and LICENSE files for more details.
#++

module LlmConnections
  # Stores a provider holding the environment's configuration, reusing one with the
  # same values or creating one, and sets the default models it names.
  #
  # Uses EnvironmentUpdateContract, which lifts the "configured from environment
  # is read-only" guard. It and InferenceProviders::EnvironmentCreateContract,
  # crucially, do not probe the LLM server: the container running the seed may
  # well start before the server does.
  class EnvSyncService
    # A JSON string from the environment variable, since nested variable names
    # cannot spell a header name such as api-version, or a Hash from
    # configuration.yml. Anything that is not an object is passed on unparsed
    # for LlmConnection's validation to refuse.
    def self.custom_headers(value)
      return {} if value.nil? || value == ""
      return value unless value.is_a?(String)

      parsed = JSON.parse(value)
      parsed.is_a?(Hash) ? parsed : value
    rescue JSON::ParserError
      value
    end

    # Only the top level is symbolized: the custom header names are sent as given.
    def initialize(env_config)
      @config = env_config.symbolize_keys
    end

    def call
      result = nil

      OpenProject::Mutex.with_advisory_lock_transaction(LlmConnection.current) do
        ApplicationRecord.transaction(requires_new: true) do
          # Loaded again under the lock. A copy read before an administrator's
          # save committed would take the environment's values for unchanged
          # and not write them.
          result = apply_to(LlmConnection.current)
          raise ActiveRecord::Rollback if result.failure?
        end
      end

      result
    end

    private

    attr_reader :config

    # The result carries the provider, which is what the seeder asks about.
    def apply_to(connection)
      provider_for_environment.bind do |provider|
        write({ llm_features_enabled: }, model: connection)
          .bind { |written| write(default_model_references(provider), model: written) }
          .bind { ServiceResult.success(result: provider) }
      end
    end

    def provider_for_environment
      stored = stored_provider
      return reuse(stored) if stored

      ::InferenceProviders::CreateService
        .new(user: User.system, contract_class: ::InferenceProviders::EnvironmentCreateContract)
        .call(**provider_settings)
    end

    # The fetch queued on creation can have given up on a server that was not up
    # yet. A list that exists is only refreshed by hand.
    def reuse(provider)
      ::Llm::SyncModelsJob.perform_later(provider.id) if provider.last_synced_at.nil?

      ServiceResult.success(result: provider)
    end

    # The headers are compared here because +where+ takes a hash value for a table
    # reference. The format is no part of it, since no variable sets one.
    def stored_provider
      InferenceProvider
        .where(provider_settings.slice(:base_url, :api_key))
        .order(:id)
        .detect { |provider| provider.custom_headers == provider_settings[:custom_headers] }
    end

    # Absent keys count as empty on purpose: the environment is the source of
    # truth here. Keeping a stored value that was removed from the
    # environment would leave, for example, an obsolete API key in use.
    def provider_settings
      @provider_settings ||= {
        base_url: config.fetch(:base_url),
        api_key: config[:api_key],
        custom_headers: self.class.custom_headers(config[:custom_headers])
      }
    end

    # Unlike the provider's values, the features switch has its own variable, so
    # an absent key leaves it as it is.
    def llm_features_enabled
      return Setting.llm_features_enabled? unless config.key?(:enabled)

      ActiveRecord::Type::Boolean.new.deserialize(config[:enabled])
    end

    def write(attributes, model:)
      UpdateService
        .new(user: User.system,
             model:,
             contract_class: EnvironmentUpdateContract)
        .call(**attributes, env_provisioned_at:, env_fingerprint: LlmConnection.env_fingerprint(config))
    end

    def env_provisioned_at
      @env_provisioned_at ||= Time.current
    end

    # The environment names a model, and on a fresh installation nothing has
    # asked the server for a catalogue yet, so the row it must reference is
    # entered here the way an administrator would enter it by hand. A row the
    # server reported is claimed the same way.
    def default_model_references(provider)
      { default_chat_model_id: model_row_id(provider, config[:default_chat_model]),
        default_embedding_model_id: model_row_id(provider, config[:default_embedding_model]) }
    end

    def model_row_id(provider, external_id)
      return if external_id.blank?

      provider.models.find_or_initialize_by(external_id:).tap { it.update!(manual: true) }.id
    end
  end
end
