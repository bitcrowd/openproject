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

require "spec_helper"
require_module_spec_helper

RSpec.describe Llm::ProviderActivity,
               with_good_job_batches: [Llm::SyncModelsJob, Llm::DetectCapabilitiesJob, Llm::CheckProviderHealthJob] do
  subject(:activity) { described_class.new(InferenceProvider.by_title) }

  let!(:provider) { create(:inference_provider) }

  def job_for(job_class) = GoodJob::Job.find_by!(job_class: job_class.name)

  it "names nothing while no job works on the provider" do
    expect(activity.for(provider)).to be_nil
    expect(activity).not_to be_any
  end

  it "is running checks while the health check waits or runs" do
    Llm::CheckProviderHealthJob.perform_later(provider.id)

    expect(activity.for(provider)).to eq(:running_checks)
    expect(activity).to be_any
  end

  it "is checking models while the list is fetched" do
    Llm::SyncModelsJob.perform_later(provider.id)

    expect(activity.for(provider)).to eq(:checking_models)
  end

  it "is checking models while their capabilities are detected" do
    Llm::DetectCapabilitiesJob.perform_later(provider.id)
    job_for(Llm::DetectCapabilitiesJob).update!(performed_at: Time.current)

    expect(activity.for(provider)).to eq(:checking_models)
  end

  it "names the earlier step while both are pending" do
    Llm::CheckProviderHealthJob.perform_later(provider.id)
    Llm::DetectCapabilitiesJob.perform_later(provider.id)

    expect(activity.for(provider)).to eq(:checking_models)
  end

  it "keeps another provider's jobs apart" do
    other = create(:inference_provider)
    Llm::CheckProviderHealthJob.perform_later(other.id)

    expect(activity.for(provider)).to be_nil
    expect(activity.for(other)).to eq(:running_checks)
  end

  it "leaves out a fetch waiting for its next attempt" do
    Llm::SyncModelsJob.set(wait: 1.hour).perform_later(provider.id)

    expect(activity.for(provider)).to be_nil
  end

  it "leaves out a finished job" do
    Llm::CheckProviderHealthJob.perform_later(provider.id)
    job_for(Llm::CheckProviderHealthJob).update!(performed_at: 1.minute.ago, finished_at: Time.current)

    expect(activity.for(provider)).to be_nil
  end

  describe "#reference" do
    def reference = described_class.new(InferenceProvider.by_title).reference

    it "stays the same while nothing changes" do
      earlier = reference

      expect(reference).to eq(earlier)
    end

    it "changes when a job starts working on a provider" do
      expect { Llm::CheckProviderHealthJob.perform_later(provider.id) }.to change { reference }
    end

    it "changes when a new report is in" do
      group = HealthReport::ResultGroup.new(key: :configuration, results: [HealthReport::Result.success(:enabled)])

      expect { provider.health_reports.create!(results: [group]) }.to change { reference }
    end
  end
end
