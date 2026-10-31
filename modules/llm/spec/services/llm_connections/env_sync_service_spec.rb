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

  let!(:connection) do
    create(:llm_connection, :with_models, base_url: "https://example.com/v1", api_key: "sk-stored")
  end

  context "with a valid configuration" do
    let(:env_config) do
      { "base_url" => "https://other.example.com/v1", "api_key" => "sk-from-env", "default_chat_model" => "qwen3.6-27b" }
    end

    it "writes the connection and its default model" do
      expect(result).to be_success

      connection.reload
      expect(connection.base_url).to eq("https://other.example.com/v1")
      expect(connection.default_chat_model.external_id).to eq("qwen3.6-27b")
    end

    it "marks the connection as written by the environment" do
      expect(result).to be_success

      expect(connection.reload.env_provisioned_at).to be_present
    end

    # The second write would change the marker if it carried another time, and
    # clear it if it carried none.
    it "stamps both of its writes with the same time" do
      expect(result).to be_success

      expect(result.result.saved_changes).not_to have_key("env_provisioned_at")
    end

    it "records which configuration it applied" do
      expect(result).to be_success

      expect(connection.reload.env_fingerprint).to eq(LlmConnection.env_fingerprint(env_config))
    end
  end

  # The previous server reported the model, so the row the default points at
  # was discovered rather than entered by the seed.
  context "when the environment moves to another server and names a model the previous one reported",
          :llm_server_helpers, :webmock do
    let(:env_config) { { "base_url" => "https://other.example.com/v1", "default_chat_model" => "qwen3.6-27b" } }

    before do
      connection.update!(connection_fingerprint: connection.settings_fingerprint)
      mock_llm_models_response("https://other.example.com/v1")
    end

    it "keeps it as the default through a refresh against the new server" do
      expect(result).to be_success

      expect(LlmConnections::SyncModelsService.new(connection.reload).call).to be_success

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

  context "when the environment changes the server of an existing connection", :webmock do
    let(:env_config) { { "base_url" => "https://other.example.com/v1", "api_key" => "sk-from-env" } }

    it "contacts neither the previous server nor the new one" do
      expect(result).to be_success

      expect(a_request(:any, %r{\Ahttps://(other\.)?example\.com/})).not_to have_been_made
    end
  end

  context "when an administrator's activation commits while the seed waits for the connection's lock" do
    let(:env_config) { { "base_url" => "https://example.com/v1", "api_key" => "sk-stored" } }
    let!(:administrators_provider) { create(:inference_provider, base_url: "https://admin.example/v1") }

    before do
      saved = false
      allow(OpenProject::Mutex).to receive(:with_advisory_lock_transaction).and_wrap_original do |original, *args, &block|
        LlmConnection.where(id: connection.id).update_all(inference_provider_id: administrators_provider.id) unless saved
        saved = true
        original.call(*args, &block)
      end
    end

    it "writes the environment's values over it" do
      expect(result).to be_success

      expect(connection.reload.base_url).to eq("https://example.com/v1")
    end
  end

  describe "the provider it points the connection at" do
    let(:env_config) { { "base_url" => "https://example.com/v1", "api_key" => "sk-stored" } }

    it "reuses the connection's provider when the values match" do
      provider_id = connection.inference_provider_id

      expect { result }.not_to change(InferenceProvider, :count)

      expect(connection.reload.inference_provider_id).to eq(provider_id)
    end

    context "when a re-seed finds the values it applied before" do
      it "reuses its provider" do
        described_class.new({ "base_url" => "https://other.example.com/v1", "api_key" => "sk-from-env" }).call
        provider_id = connection.reload.inference_provider_id

        expect { described_class.new({ "base_url" => "https://other.example.com/v1/", "api_key" => "sk-from-env" }).call }
          .not_to change(InferenceProvider, :count)

        expect(connection.reload.inference_provider_id).to eq(provider_id)
      end
    end

    context "when an administrator activated another provider since" do
      let(:administrators_provider) { create(:inference_provider, base_url: "https://admin.example/v1") }

      before { connection.update!(inference_provider: administrators_provider) }

      it "points the connection back at the stored one with the environment's values" do
        stored = InferenceProvider.find_by!(base_url: "https://example.com/v1")

        expect { result }.not_to change(InferenceProvider, :count)

        expect(connection.reload.inference_provider).to eq(stored)
      end

      it "leaves the administrator's provider stored" do
        expect(result).to be_success

        expect(administrators_provider.reload.base_url).to eq("https://admin.example/v1")
      end
    end

    context "when only the API key differs" do
      let(:env_config) { { "base_url" => "https://example.com/v1", "api_key" => "sk-rotated" } }

      it "adds a provider and keeps the previous one stored" do
        previous = connection.inference_provider

        expect { result }.to change(InferenceProvider, :count).by(1)

        expect(connection.reload.api_key).to eq("sk-rotated")
        expect(previous.reload.api_key).to eq("sk-stored")
      end
    end

    context "when only the custom headers differ" do
      let(:env_config) do
        { "base_url" => "https://example.com/v1", "api_key" => "sk-stored",
          "custom_headers" => '{"api-version":"2024-02-01"}' }
      end

      it "adds a provider" do
        expect { result }.to change(InferenceProvider, :count).by(1)

        expect(connection.reload.custom_headers).to eq("api-version" => "2024-02-01")
      end
    end

    context "when the same custom headers are written in another order" do
      let(:env_config) do
        { "base_url" => "https://example.com/v1", "api_key" => "sk-stored",
          "custom_headers" => '{"b":"2","a":"1"}' }
      end

      before { connection.inference_provider.update!(custom_headers: { "a" => "1", "b" => "2" }) }

      it "reuses the provider" do
        expect { result }.not_to change(InferenceProvider, :count)
      end
    end

    context "when the environment moves to a new server" do
      let(:env_config) { { "base_url" => "https://other.example.com:8443/v1/" } }

      before { connection.inference_provider.update!(api_format: "openrouter") }

      it "names the new provider after the host and port" do
        expect(result).to be_success

        expect(connection.reload.inference_provider.title).to eq("other.example.com:8443")
      end

      it "takes the format of the active provider, since no variable sets one" do
        expect(result).to be_success

        expect(connection.reload.api_format).to eq("openrouter")
      end
    end

    context "when a stored provider with the same values speaks another format" do
      let(:env_config) { { "base_url" => "https://admin.example/v1", "api_key" => "sk-admin" } }
      let!(:stored) do
        create(:inference_provider, base_url: "https://admin.example/v1", api_key: "sk-admin", api_format: "openrouter")
      end

      it "reuses it, since no variable sets a format" do
        expect { result }.not_to change(InferenceProvider, :count)

        expect(connection.reload.inference_provider).to eq(stored)
      end
    end

    context "on an installation with no connection stored" do
      let(:env_config) { { "base_url" => "https://example.com/v1", "api_key" => "sk-from-env" } }
      let!(:connection) { nil }

      it "creates both, with the default format" do
        expect(result).to be_success

        expect(LlmConnection.active_connection)
          .to have_attributes(base_url: "https://example.com/v1", api_key: "sk-from-env", api_format: "openai")
      end
    end

    context "when the connection cannot take the environment's values" do
      let(:env_config) { { "base_url" => "https://other.example.com/v1", "default_chat_model" => "bge-m3" } }

      before do
        create(:llm_capability_verdict, llm_connection: connection, model_id: "bge-m3", capability: "embeddings",
                                        state: "supported", source: "admin")
      end

      it "stores no provider either" do
        expect { result }.not_to change(InferenceProvider, :count)

        expect(result).to be_failure
      end
    end
  end

  context "with custom headers as a JSON object" do
    let(:env_config) do
      { "base_url" => "https://example.com/v1", "custom_headers" => '{"api-version":"2024-02-01","X-Gateway":"on"}' }
    end

    it "stores the header names exactly as given" do
      expect(result).to be_success
      expect(connection.reload.custom_headers).to eq("api-version" => "2024-02-01", "X-Gateway" => "on")
    end
  end

  context "with custom headers as a Hash" do
    let(:env_config) do
      { "base_url" => "https://example.com/v1", "custom_headers" => { "api-version" => "2024-02-01" } }
    end

    it "stores the header names exactly as given" do
      expect(result).to be_success
      expect(connection.reload.custom_headers).to eq("api-version" => "2024-02-01")
    end
  end

  context "without custom headers while some are stored" do
    let(:env_config) { { "base_url" => "https://example.com/v1" } }

    before { connection.inference_provider.update!(custom_headers: { "api-version" => "2024-02-01" }) }

    it "no longer sends them" do
      expect(result).to be_success
      expect(connection.reload.custom_headers).to eq({})
    end
  end

  context "with custom headers that are not a JSON object" do
    let(:env_config) { { "base_url" => "https://example.com/v1", "custom_headers" => '["api-version"]' } }

    before { connection.inference_provider.update!(custom_headers: { "api-version" => "2024-02-01" }) }

    it "fails and keeps the stored headers" do
      expect(result).to be_failure
      expect(result.errors).to be_of_kind(:custom_headers, :invalid)
      expect(connection.reload.custom_headers).to eq("api-version" => "2024-02-01")
    end
  end

  context "when the default model cannot be bound" do
    let(:env_config) do
      { "base_url" => "https://other.example.com/v1", "api_key" => "sk-from-env", "default_chat_model" => "bge-m3" }
    end

    before do
      create(:llm_capability_verdict, llm_connection: connection, model_id: "bge-m3", capability: "embeddings",
                                      state: "supported", source: "admin")
    end

    it "fails and keeps the stored connection as it was" do
      expect(result).to be_failure

      connection.reload
      expect(connection.base_url).to eq("https://example.com/v1")
      expect(connection.api_key).to eq("sk-stored")
      expect(connection.default_chat_model_id).to be_nil
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

  context "when the connection itself is invalid" do
    let(:env_config) { { "base_url" => "not a url" } }

    it "fails and keeps the stored connection as it was" do
      expect(result).to be_failure
      expect(connection.reload.base_url).to eq("https://example.com/v1")
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
end
