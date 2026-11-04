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
  module Validators
    # What the stored catalogue says, without asking the server anything.
    class ModelValidator < HealthReports::ValidatorGroup
      STALE_AFTER = 30.days

      def self.key = :models

      private

      def validate
        register_checks(:catalogue_present, :catalogue_fresh, *defaults_on_this_provider.keys)

        catalogue_present
        catalogue_fresh
        defaults_on_this_provider.each { |key, llm_model| check_default(key, llm_model) }
      end

      # Never a failure. A gateway may expose chat and no catalogue at all, which
      # is why models can be entered by hand in the first place.
      def catalogue_present
        return pass_check(:catalogue_present) if subject.available_model_ids.any?

        warn_check(:catalogue_present, :no_models)
      end

      def catalogue_fresh
        fetched_at = subject.last_synced_at

        if fetched_at.blank?
          warn_check(:catalogue_fresh, :catalogue_never_fetched)
        elsif fetched_at < STALE_AFTER.ago
          # Context is serialized to jsonb, so a Time has to be formatted here.
          warn_check(:catalogue_fresh, :catalogue_stale, context: { fetched_at: I18n.l(fetched_at.to_date) })
        else
          pass_check(:catalogue_fresh)
        end
      end

      # A default is a single model, so only the report of the provider offering
      # it can say anything about it.
      def defaults_on_this_provider
        @defaults_on_this_provider ||= begin
          connection = LlmConnection.current

          { default_chat_model: connection.default_chat_model,
            default_embedding_model: connection.default_embedding_model }
            .select { |_, llm_model| llm_model&.inference_provider_id == subject.id }
        end
      end

      def check_default(key, llm_model)
        return pass_check(key) if llm_model.active?

        warn_check(key, :default_model_missing, context: { model: llm_model.external_id })
      end
    end
  end
end
