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

RSpec.describe Llm::SyncModelsJob, :llm_server_helpers, :webmock do
  let(:base_url) { "https://example.com/v1" }
  let!(:provider) { create(:inference_provider, base_url:) }

  it "refreshes the model list of the provider" do
    request = mock_llm_models_response(base_url)

    described_class.perform_now(provider.id)

    expect(request).to have_been_made.once
    expect(provider.reload.available_model_ids).to contain_exactly("qwen3.6-27b", "bge-m3")
  end

  it "does nothing once the provider is gone" do
    expect { described_class.perform_now(0) }.not_to raise_error
  end

  it "leaves another provider alone" do
    other = create(:inference_provider, base_url: "https://other.example/v1")
    mock_llm_models_response(base_url)

    described_class.perform_now(provider.id)

    expect(other.models).to be_empty
  end

  # The job exists for the startup race with a provisioned LLM sidecar, which
  # either is not listening yet or answers before it has loaded its model.
  {
    "refuses the connection" => { raise_error: Errno::ECONNREFUSED },
    "times out" => { timeout: true },
    "is unavailable" => { response_code: 503 },
    "throttles requests" => { response_code: 429 }
  }.each do |situation, response|
    it "tries again when the server #{situation}" do
      mock_llm_models_response(base_url, **response)

      expect { described_class.perform_now(provider.id) }.to have_enqueued_job(described_class)
    end
  end

  describe "a server that is up but lists no models yet" do
    {
      "an empty list" => { models: [] },
      "Ollama's list before its first pull" => { body: { object: "list", data: nil }.to_json }
    }.each do |answer, response|
      it "tries again when a provider that has never synced gets #{answer}" do
        mock_llm_models_response(base_url, **response)

        expect { described_class.perform_now(provider.id) }.to have_enqueued_job(described_class)
      end
    end

    it "keeps trying on the retries, after the empty sync has recorded last_synced_at" do
      mock_llm_models_response(base_url, models: [])
      described_class.perform_now(provider.id)

      perform_enqueued_jobs(only: described_class)

      expect(provider.reload.last_synced_at).to be_present
      expect(described_class).to have_been_enqueued.exactly(:once)
    end

    it "stops once the server lists a model" do
      mock_llm_models_response(base_url, models: [])
      described_class.perform_now(provider.id)
      mock_llm_models_response(base_url)

      perform_enqueued_jobs(only: described_class)

      expect(described_class).not_to have_been_enqueued
    end

    it "does not try again when the server lists only a model entered by hand" do
      create(:llm_model, :manual, inference_provider: provider, external_id: "qwen3.6-27b")
      mock_llm_models_response(base_url, models: [{ id: "qwen3.6-27b" }])

      expect { described_class.perform_now(provider.id) }.not_to have_enqueued_job(described_class)
    end

    it "tries again while the server lists nothing, whatever was entered by hand" do
      create(:llm_model, :manual, inference_provider: provider, external_id: "qwen3.6-27b")
      mock_llm_models_response(base_url, models: [])

      expect { described_class.perform_now(provider.id) }.to have_enqueued_job(described_class)
    end

    it "tries again when only an earlier sync saw a model" do
      create(:llm_model, :manual, inference_provider: provider, external_id: "qwen3.6-27b", last_seen_at: 1.hour.ago)
      mock_llm_models_response(base_url, models: [])

      expect { described_class.perform_now(provider.id) }.to have_enqueued_job(described_class)
    end

    it "does not try again for a provider that has synced before" do
      provider.update!(last_synced_at: 1.day.ago)
      mock_llm_models_response(base_url, models: [])

      expect { described_class.perform_now(provider.id) }.not_to have_enqueued_job(described_class)
    end
  end

  {
    "has no model list at this URL" => { response_code: 404 },
    "does not implement the model list" => { response_code: 501 },
    "rejects the API key" => { response_code: 401 },
    "answers with something other than a model list" => { body: "<html></html>" }
  }.each do |situation, response|
    it "does not try again when the server #{situation}" do
      mock_llm_models_response(base_url, **response)

      expect { described_class.perform_now(provider.id) }.not_to have_enqueued_job(described_class)
    end
  end

  it "warns once it gives up on a failure that will not pass on its own" do
    mock_llm_models_response(base_url, response_code: 404)
    warnings = []
    allow(Rails.logger).to receive(:warn) { |*args, &message| warnings << (message ? message.call : args.first) }

    described_class.perform_now(provider.id)

    expect(warnings).to include(a_string_including("will not be retried", "Server responded with 404"))
  end

  it "tries again when two syncs raced to store the same model" do
    mock_llm_models_response(base_url)
    allow(LlmConnections::SyncModelsService).to receive(:new).and_wrap_original do |original, stored|
      allow(stored.models).to receive(:find_or_initialize_by).and_raise(ActiveRecord::RecordNotUnique)
      original.call(stored)
    end

    expect { described_class.perform_now(provider.id) }.to have_enqueued_job(described_class)
  end

  it "logs what raised and does not try again" do
    allow(LlmConnections::SyncModelsService).to receive(:new).and_raise("unexpected")
    logged = []
    allow(Rails.logger).to receive(:error) { |&message| logged << message.call }

    expect { described_class.perform_now(provider.id) }.not_to raise_error

    expect(logged).to include(a_string_including("provider #{provider.id}"))
  end
end
