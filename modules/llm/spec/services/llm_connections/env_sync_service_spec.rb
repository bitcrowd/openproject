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

RSpec.describe LlmConnections::EnvSyncService do
  subject(:result) { described_class.new(env_config).call }

  let!(:provider) do
    create(:inference_provider, :with_models, base_url: "https://example.com/v1", api_key: "sk-stored")
  end
  let(:connection) { LlmConnection.current }

  context "with a valid configuration" do
    let(:env_config) do
      { "base_url" => "https://other.example.com/v1", "api_key" => "sk-from-env", "default_chat_model" => "qwen3.6-27b" }
    end

    it "stores a provider with the values and its default model" do
      expect(result).to be_success

      expect(result.result).to have_attributes(base_url: "https://other.example.com/v1", api_key: "sk-from-env")
      expect(connection.reload.default_chat_model)
        .to have_attributes(external_id: "qwen3.6-27b", inference_provider: result.result)
    end

    it "leaves the stored provider as it was" do
      expect(result).to be_success

      expect(provider.reload).to have_attributes(base_url: "https://example.com/v1", api_key: "sk-stored")
    end

    it "marks the connection as written by the environment" do
      expect(result).to be_success

      expect(connection.reload.env_provisioned_at).to be_present
    end

    it "records which configuration it applied" do
      expect(result).to be_success

      expect(connection.reload.env_fingerprint).to eq(LlmConnection.env_fingerprint(env_config))
    end

    it "fetches the list of the new provider in the background" do
      expect { result }.to have_enqueued_job(Llm::SyncModelsJob).once
    end
  end

  # The server reported the model, so the row the default points at was discovered
  # rather than entered by the seed.
  context "when the environment names a model the server reported", :llm_server_helpers, :webmock do
    let(:env_config) do
      { "base_url" => "https://example.com/v1", "api_key" => "sk-stored", "default_chat_model" => "qwen3.6-27b" }
    end

    before { mock_llm_models_response("https://example.com/v1") }

    it "keeps it as the default through a refresh" do
      expect(result).to be_success

      expect(LlmConnections::SyncModelsService.new(result.result).call).to be_success

      expect(connection.reload.default_chat_model&.external_id).to eq("qwen3.6-27b")
    end
  end

  context "with the features switch given as a string" do
    let(:env_config) { { "base_url" => "https://example.com/v1", "enabled" => "false" } }

    before { Setting.llm_features_enabled = true }

    it "casts it rather than taking any string for true" do
      expect(result).to be_success

      expect(Setting.llm_features_enabled?).to be(false)
    end
  end

  context "without the features switch" do
    let(:env_config) { { "base_url" => "https://example.com/v1" } }

    before { Setting.llm_features_enabled = true }

    it "leaves the instance-wide switch as it is" do
      expect(result).to be_success

      expect(Setting.llm_features_enabled?).to be(true)
    end
  end

  context "when the environment names another server", :webmock do
    let(:env_config) { { "base_url" => "https://other.example.com/v1", "api_key" => "sk-from-env" } }

    it "contacts neither the stored server nor the new one" do
      expect(result).to be_success

      expect(a_request(:any, %r{\Ahttps://(other\.)?example\.com/})).not_to have_been_made
    end
  end

  describe "the provider it uses" do
    let(:env_config) { { "base_url" => "https://example.com/v1", "api_key" => "sk-stored" } }

    it "reuses a stored one when the values match" do
      expect { result }.not_to change(InferenceProvider, :count)

      expect(result.result).to eq(provider)
    end

    it "does not fetch a list that is stored" do
      expect { result }.not_to have_enqueued_job(Llm::SyncModelsJob)
    end

    it "fetches the list of a stored provider that has none yet" do
      provider.update!(last_synced_at: nil)

      expect { result }.to have_enqueued_job(Llm::SyncModelsJob).with(provider.id)
    end

    context "when a re-seed finds the values it applied before" do
      it "reuses its provider" do
        applied = described_class.new({ "base_url" => "https://other.example.com/v1", "api_key" => "sk-from-env" }).call.result

        again = nil
        expect { again = described_class.new({ "base_url" => "https://other.example.com/v1/", "api_key" => "sk-from-env" }).call }
          .not_to change(InferenceProvider, :count)

        expect(again.result).to eq(applied)
      end
    end

    context "when only the API key differs" do
      let(:env_config) { { "base_url" => "https://example.com/v1", "api_key" => "sk-rotated" } }

      it "adds a provider and keeps the previous one stored" do
        expect { result }.to change(InferenceProvider, :count).by(1)

        expect(result.result.api_key).to eq("sk-rotated")
        expect(provider.reload.api_key).to eq("sk-stored")
      end
    end

    context "when only the custom headers differ" do
      let(:env_config) do
        { "base_url" => "https://example.com/v1", "api_key" => "sk-stored",
          "custom_headers" => '{"api-version":"2024-02-01"}' }
      end

      it "adds a provider" do
        expect { result }.to change(InferenceProvider, :count).by(1)

        expect(result.result.custom_headers).to eq("api-version" => "2024-02-01")
      end
    end

    context "when the same custom headers are written in another order" do
      let(:env_config) do
        { "base_url" => "https://example.com/v1", "api_key" => "sk-stored",
          "custom_headers" => '{"b":"2","a":"1"}' }
      end

      before { provider.update!(custom_headers: { "a" => "1", "b" => "2" }) }

      it "reuses the provider" do
        expect { result }.not_to change(InferenceProvider, :count)
      end
    end

    context "when the environment names a new server" do
      let(:env_config) { { "base_url" => "https://other.example.com:8443/v1/" } }

      it "names the new provider after the host and port" do
        expect(result).to be_success

        expect(result.result.title).to eq("other.example.com:8443")
      end

      it "takes the default format, since no variable sets one" do
        expect(result).to be_success

        expect(result.result.api_format).to eq("openai")
      end
    end

    context "when a stored provider with the same values speaks another format" do
      let(:env_config) { { "base_url" => "https://admin.example/v1", "api_key" => "sk-admin" } }
      let!(:stored) do
        create(:inference_provider, base_url: "https://admin.example/v1", api_key: "sk-admin", api_format: "openrouter")
      end

      it "reuses it, since no variable sets a format" do
        expect { result }.not_to change(InferenceProvider, :count)

        expect(result.result).to eq(stored)
      end
    end

    context "on an installation with nothing stored" do
      let(:env_config) { { "base_url" => "https://example.com/v1", "api_key" => "sk-from-env" } }
      let!(:provider) { nil }

      it "creates both, with the default format" do
        expect(result).to be_success

        expect(result.result)
          .to have_attributes(base_url: "https://example.com/v1", api_key: "sk-from-env", api_format: "openai")
        expect(connection.env_provisioned_at).to be_present
      end
    end
  end

  context "with custom headers as a JSON object" do
    let(:env_config) do
      { "base_url" => "https://example.com/v1", "custom_headers" => '{"api-version":"2024-02-01","X-Gateway":"on"}' }
    end

    it "stores the header names exactly as given" do
      expect(result).to be_success
      expect(result.result.custom_headers).to eq("api-version" => "2024-02-01", "X-Gateway" => "on")
    end
  end

  context "with custom headers as a Hash" do
    let(:env_config) do
      { "base_url" => "https://example.com/v1", "custom_headers" => { "api-version" => "2024-02-01" } }
    end

    it "stores the header names exactly as given" do
      expect(result).to be_success
      expect(result.result.custom_headers).to eq("api-version" => "2024-02-01")
    end
  end

  context "with custom headers that are not a JSON object" do
    let(:env_config) { { "base_url" => "https://example.com/v1", "custom_headers" => '["api-version"]' } }

    it "fails and adds no provider" do
      expect { result }.not_to change(InferenceProvider, :count)

      expect(result).to be_failure
      expect(result.errors).to be_of_kind(:custom_headers, :invalid)
    end
  end

  context "when the default model cannot be bound" do
    let(:env_config) do
      { "base_url" => "https://example.com/v1", "api_key" => "sk-stored", "default_chat_model" => "bge-m3" }
    end

    before do
      create(:llm_capability_verdict, inference_provider: provider, model_id: "bge-m3", capability: "embeddings",
                                      state: "supported", source: "admin")
    end

    it "fails and keeps no default" do
      expect(result).to be_failure

      expect(connection.reload.default_chat_model_id).to be_nil
    end

    it "does not mark the connection as written by the environment" do
      expect(result).to be_failure

      expect(connection.reload.env_provisioned_at).to be_nil
    end

    it "keeps the time the environment last wrote the connection" do
      applied_at = 1.day.ago.change(usec: 0)
      connection.update_columns(env_provisioned_at: applied_at)

      expect(result).to be_failure

      expect(connection.reload.env_provisioned_at).to eq(applied_at)
    end
  end

  context "when the configured server is invalid" do
    let(:env_config) { { "base_url" => "not a url" } }

    it "fails and adds no provider" do
      expect { result }.not_to change(InferenceProvider, :count)

      expect(result).to be_failure
    end

    it "does not mark the connection as written by the environment" do
      expect(result).to be_failure

      expect(connection.reload.env_provisioned_at).to be_nil
    end
  end
end
