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
  # Re-checks every provider, so a server that dies after setup does not stay
  # green until somebody happens to look.
  #
  # Deliberately does *not* set deep_health_check: the inference group spends a
  # real completion, which is billed on a hosted provider. An unattended job must
  # not run up a bill, so the schedule covers everything that is free -- an
  # expired key, a withdrawn model, a binding that stopped resolving -- and the
  # billed round trip stays with what an administrator starts: a check, or a
  # fetch of a provider's model list.
  class HealthCheckJob < ApplicationJob
    CRON_JOB_KEY = name.to_sym

    queue_with_priority :low

    class << self
      # Keeps the cron idle while there is nothing to check, rather than waking
      # every six hours to find no provider.
      def toggle_cron_job
        if runnable?
          GoodJob::Setting.cron_key_enable(CRON_JOB_KEY) unless GoodJob::Setting.cron_key_enabled?(CRON_JOB_KEY)
        elsif GoodJob::Setting.cron_key_enabled?(CRON_JOB_KEY)
          GoodJob::Setting.cron_key_disable(CRON_JOB_KEY)
        end
      end

      def runnable?
        return false unless OpenProject::FeatureDecisions.llm_connection_active?

        LlmConnection.available?
      end
    end

    def perform
      return unless self.class.runnable?

      InferenceProvider.find_each { |provider| check(provider) }
    end

    private

    # One provider's failure must not leave the others without a report.
    def check(provider)
      Llm::Validators::ConnectionValidator.new(provider).call.save!
    rescue StandardError => e
      Rails.logger.error do
        "LLM health check failed for provider #{provider.id}: #{e.class}\n" \
          "#{Rails.backtrace_cleaner.clean(Array(e.backtrace)).join("\n")}"
      end
    end
  end
end
