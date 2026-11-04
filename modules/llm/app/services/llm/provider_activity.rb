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
  # What the background jobs are doing for each inference provider, read from
  # GoodJob rather than stored, so a worker that dies leaves no state behind that
  # says otherwise.
  class ProviderActivity
    # In the order a model list fetch runs them: while both are pending, the
    # provider is still at the first step.
    STEPS = {
      checking_models: [Llm::SyncModelsJob, Llm::DetectCapabilitiesJob],
      running_checks: [Llm::CheckProviderHealthJob]
    }.freeze

    delegate :any?, to: :steps

    def initialize(providers)
      @providers = providers
    end

    def for(provider) = steps[provider.id]

    # Changes whenever a row would show something else, so that polling
    # re-renders the list only then, and an open menu stays open meanwhile.
    def reference
      Digest::SHA256.hexdigest([steps, latest_report_ids].to_json)
    end

    private

    attr_reader :providers

    def steps
      @steps ||= providers.each_with_object({}) do |provider, steps|
        step, = STEPS.find { |_, jobs| jobs.any? { |job| busy_keys.include?(key(job, provider)) } }
        steps[provider.id] = step if step
      end
    end

    # Queued or running. A retry waiting for its time does not count: a failed
    # fetch can wait hours for its next attempt, and the health check that
    # followed it already says what went wrong.
    def busy_keys
      @busy_keys ||= GoodJob::Job.where(concurrency_key: all_keys).unfinished.only_scheduled
                                 .distinct.pluck(:concurrency_key).to_set
    end

    def all_keys
      providers.flat_map { |provider| STEPS.values.flatten.map { |job| key(job, provider) } }
    end

    def key(job, provider) = job.new(provider.id).good_job_concurrency_key

    def latest_report_ids
      HealthReport.where(subject: providers).group(:subject_id).maximum(:id)
    end
  end
end
