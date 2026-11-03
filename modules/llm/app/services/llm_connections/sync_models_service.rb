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
  # Refreshes the model list from the remote server.
  #
  # Kept separate from the contract probe so the same path serves the "Refresh
  # models" button, the update service and the environment seeder.
  class SyncModelsService
    # A catalogue no administrator could read through anyway, and an upper bound
    # on how many rows one unbounded response can write.
    MAX_CARDS = 2_000

    def initialize(provider)
      @provider = provider
    end

    def call
      store(fetched_cards)
      Llm::DetectCapabilitiesJob.perform_later(provider.id)

      ServiceResult.success(result: provider)
    rescue Llm::Client::Error => e
      failed(e, "failed: #{e.class} #{e.message}", e.message)
    rescue ActiveRecord::ActiveRecordError => e
      # Two syncs racing find_or_initialize_by can hit a uniqueness violation.
      failed(e, "could not be stored: #{e.class}", e.class.to_s)
    end

    private

    attr_reader :provider

    def failed(error, reason, errors)
      Rails.logger.info { "LLM model sync for provider #{provider.id} #{reason}" }

      ServiceResult.failure(errors:, result: error)
    end

    def adapter
      @adapter ||= Llm::Adapters.for(provider)
    end

    def fetched_cards
      capped(storable(adapter.models))
    end

    def storable(cards)
      oversized, fitting = cards.partition { |card| card.fetch(:id).to_s.length > LlmModel::MAX_EXTERNAL_ID_LENGTH }
      return cards if oversized.empty?

      Rails.logger.warn do
        "The LLM server of provider #{provider.id} listed #{oversized.size} models with an id longer than " \
          "#{LlmModel::MAX_EXTERNAL_ID_LENGTH} characters; skipping them"
      end
      fitting
    end

    def capped(cards)
      return cards if cards.size <= MAX_CARDS

      Rails.logger.warn do
        "The LLM server of provider #{provider.id} listed #{cards.size} models; storing the first #{MAX_CARDS}"
      end
      cards.first(MAX_CARDS)
    end

    def store(cards)
      ActiveRecord::Base.transaction do
        provider.update!(sync_attributes)
        upsert(cards)
        withdraw_models_absent_from(cards)
        discard_verdicts_for_vanished_models
      end

      EnrichCapabilitiesService.new(provider).call
    end

    def sync_attributes
      now = Time.current

      {
        last_synced_at: now,
        last_connected_at: now,
        options: provider.options.merge("server_flavor" => adapter.server_flavor)
      }
    end

    def upsert(cards)
      now = Time.current

      cards.each do |card|
        model = provider.models.find_or_initialize_by(external_id: card.fetch(:id))
        model.update!(raw_metadata: merged_metadata(model, card),
                      last_seen_at: now,
                      active: true)
      end
    end

    # Deactivated rather than deleted, so a binding or verdict pointing at one
    # still has something to name. Manual entries are left alone: the server was
    # never the thing that confirmed them.
    # where.not against an empty id list matches nothing, so an empty catalogue
    # needs its own branch to withdraw everything discovered.
    def withdraw_models_absent_from(cards)
      ids = cards.map { |card| card.fetch(:id) }
      scope = provider.models.discovered
      scope = scope.where.not(external_id: ids) if ids.any?

      scope.update_all(active: false)
    end

    # The administrator's context-window override is theirs, and a routine
    # refresh must not silently discard it.
    #
    # The incoming card is stripped of the override's key first. Without that, a
    # server sending "admin_context_window" of its own would have it stored
    # verbatim and reported as an administrator's.
    def merged_metadata(model, card)
      raw = normalized_window(card.fetch(:raw, {})).except("admin_context_window")
      admin_window = model.raw_metadata["admin_context_window"]

      admin_window ? raw.merge("admin_context_window" => admin_window) : raw
    end

    # OpenRouter and gateways following it publish the window as
    # +context_length+, where vLLM and SGLang report +max_model_len+, the
    # operator's actual limit and therefore the better figure of the two.
    def normalized_window(raw)
      return raw if raw["context_length"].blank? || raw["max_model_len"].present?

      raw.merge("context_window" => raw["context_length"])
    end

    # Same deployment, but a model is gone. Its verdict is meaningless now,
    # except an administrator's assertion: an operator restarting a server must
    # not silently lose one.
    def discard_verdicts_for_vanished_models
      known = provider.available_model_ids
      scope = provider.capability_verdicts.where.not(source: "admin")
      scope = scope.where.not(model_id: known) if known.any?

      scope.delete_all
    end
  end
end
