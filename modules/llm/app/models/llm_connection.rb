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

# What AI features use across all inference providers: the default models, the
# model each feature is bound to and what the environment provisioned.
#
# A single row, reached through +current+. The servers themselves and their models
# are on InferenceProvider.
class LlmConnection < ApplicationRecord
  DEFAULT_IDENTIFIER = "default"

  # Written through to Setting.llm_features_enabled by
  # LlmConnections::UpdateService, so the environment seed can set the
  # instance-wide switch together with the rest.
  attribute :llm_features_enabled, :boolean, default: -> { Setting.llm_features_enabled? }

  belongs_to :default_chat_model, class_name: "LlmModel", optional: true
  belongs_to :default_embedding_model, class_name: "LlmModel", optional: true
  has_many :feature_bindings, class_name: "LlmFeatureBinding", dependent: :delete_all

  validates :identifier, presence: true

  class << self
    # Identifying attributes are left unset here and filled in by
    # LlmConnections::SetAttributesService as system changes, so that they do not
    # register as user-made changes to non-writable attributes.
    # Keyed, so the stored value gives away nothing about the API key it covers.
    def env_fingerprint(config = Setting.llm_connection)
      key = Rails.application.key_generator.generate_key("llm connection environment")

      OpenSSL::HMAC.hexdigest("SHA256", key, canonical_env(config).to_json)
    end

    # The same headers can reach the setting as a hash or as a JSON string, in
    # any order.
    def canonical_env(config)
      env = config.to_h.transform_keys(&:to_s)
      env["custom_headers"] = LlmConnections::EnvSyncService.custom_headers(env["custom_headers"])

      sorted_deeply(env)
    end

    def sorted_deeply(value)
      return value unless value.is_a?(Hash)

      value.transform_keys(&:to_s).sort.to_h { |key, nested| [key, sorted_deeply(nested)] }
    end

    def current
      first || create_or_find_by!(identifier: DEFAULT_IDENTIFIER)
    end

    # Whether LLM-backed features may run right now. This is the predicate
    # sibling features gate on; see #77783.
    #
    # Deliberately does not ask whether a provider was ever reached: one
    # provisioned from the environment is never probed, and must still count.
    def available?
      OpenProject::FeatureDecisions.llm_connection_active? &&
        Setting.llm_features_enabled? &&
        InferenceProvider.exists?
    end
  end

  def configured_from_env?
    Setting.llm_connection.present? && provisioned_from_env?
  end

  # Reads the stored marker: SetAttributesService clears the attribute before the
  # contract asks, which must not let a crafted save unlock the record.
  def provisioned_from_env? = persisted? && env_provisioned_at_in_database.present?

  def env_pending? = Setting.llm_connection.present? && !provisioned_from_env?

  def env_changed_since_applied?
    applied = env_fingerprint_in_database

    configured_from_env? && applied.present? && applied != self.class.env_fingerprint
  end

  def env_named_default?(llm_model)
    configured_from_env? &&
      LlmModel::CONNECTION_DEFAULTS.any? { attribute_in_database(it) == llm_model.id }
  end

  def default_model_for(feature) = feature.embedding? ? default_embedding_model : default_chat_model
end
