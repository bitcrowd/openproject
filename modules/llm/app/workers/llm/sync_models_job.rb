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

module Llm
  # Refreshes the cached model catalogue of one provider out of band.
  #
  # Used when a provider is created, and by the environment seeder, which must not
  # block on -- or fail because of -- an LLM server that has not finished starting.
  class SyncModelsJob < ApplicationJob
    include GoodJob::ActiveJobExtensions::Concurrency

    class SyncFailed < StandardError; end
    class NoModelsYet < StandardError; end

    Failure = Data.define(:error, :reason)

    good_job_control_concurrency_with(enqueue_limit: 1, perform_limit: 1,
                                      key: -> { "#{self.class.name}-#{arguments.first}" })

    # The tenth and last attempt starts roughly 4.5 hours after the first.
    retry_on SyncFailed, wait: :polynomially_longer, attempts: 10

    # An empty sync records last_synced_at like any other, so whether the provider
    # had never synced is taken on the first attempt and carried through the
    # retries.
    def serialize
      super.merge("never_synced" => @never_synced)
    end

    def deserialize(job_data)
      super
      @never_synced = job_data["never_synced"]
    end

    def perform(inference_provider_id)
      provider = InferenceProvider.find_by(id: inference_provider_id)
      return if provider.nil?

      @never_synced = provider.last_synced_at.nil? if @never_synced.nil?
      failure = failure_for(provider)
      return if failure.nil?

      raise SyncFailed, failure.reason if transient?(failure.error)

      Rails.logger.warn { "LLM model sync failed and will not be retried: #{failure.reason}" }
    end

    private

    def failure_for(provider)
      started_at = Time.current
      result = LlmConnections::SyncModelsService.new(provider).call
      return still_loading(provider, since: started_at) if result.success?

      Failure.new(error: result.result, reason: result.errors.to_s)
    rescue StandardError => e
      Rails.logger.error { "LLM model sync failed for provider #{provider.id}: #{e.class}" }
      Failure.new(error: e, reason: e.class.to_s)
    end

    # An Ollama sidecar answers with an empty list while it still pulls its model.
    def still_loading(provider, since:)
      return unless @never_synced && provider.models.where(last_seen_at: since..).none?

      Failure.new(error: NoModelsYet.new, reason: "No models listed yet")
    end

    def transient?(error)
      case error
      when NoModelsYet, ActiveRecord::ActiveRecordError then true
      else Llm::Errors.transient?(error)
      end
    end
  end
end
