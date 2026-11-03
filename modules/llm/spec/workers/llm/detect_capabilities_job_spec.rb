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

RSpec.describe Llm::DetectCapabilitiesJob, :llm_server_helpers, :webmock do
  let(:base_url) { "https://example.com/v1" }
  let!(:provider) { create(:inference_provider, :with_models, base_url:) }

  it "probes the likely embedding models of the provider" do
    mock_llm_embeddings_response(base_url)

    described_class.perform_now(provider.id)

    expect(provider.capability_verdicts.pluck(:model_id, :source)).to eq([["bge-m3", "probe"]])
  end

  it "leaves another provider alone" do
    other = create(:inference_provider, :with_models, base_url: "https://other.example/v1")
    mock_llm_embeddings_response(base_url)

    described_class.perform_now(provider.id)

    expect(other.capability_verdicts).to be_empty
  end

  it "does nothing once the provider is gone" do
    expect { described_class.perform_now(0) }.not_to raise_error
  end

  it "logs what went wrong without the error's message" do
    allow(LlmConnections::DetectCapabilitiesService).to receive(:new)
      .and_raise(ActiveRecord::RecordNotFound, "sk-leaked")
    logged = []
    allow(Rails.logger).to receive(:error) { |&message| logged << message.call }

    expect { described_class.perform_now(provider.id) }.not_to raise_error

    expect(logged).to include(
      a_string_starting_with("LLM capability detection failed for provider #{provider.id}: ActiveRecord::RecordNotFound\n")
    )
    expect(logged.join).to match(%r{app/workers/llm/detect_capabilities_job\.rb:\d+})
    expect(logged.join).not_to include("sk-leaked")
  end

  it "keeps a single run waiting per provider however often it is enqueued", with_good_job: described_class do
    other = create(:inference_provider)

    2.times { described_class.set(wait: 1.minute).perform_later(provider.id) }
    described_class.set(wait: 1.minute).perform_later(other.id)

    expect(GoodJob::Job.where(job_class: described_class.name, finished_at: nil).count).to eq(2)
  end
end
