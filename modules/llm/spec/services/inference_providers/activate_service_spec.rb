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

RSpec.describe InferenceProviders::ActivateService, :llm_server_helpers, :webmock do
  subject(:result) { described_class.new(user: create(:admin), model: provider).call }

  let(:elsewhere) { "https://elsewhere.example/v1" }
  let(:provider) { create(:inference_provider, base_url: elsewhere, api_key: "sk-elsewhere") }

  context "with no connection stored yet" do
    let!(:models_request) { mock_llm_models_response(elsewhere) }

    it "creates the connection, pointing at the provider" do
      expect(result).to be_success

      expect(LlmConnection.active_connection)
        .to have_attributes(persisted?: true, identifier: LlmConnection::DEFAULT_IDENTIFIER, inference_provider: provider)
    end

    it "fills the catalogue" do
      expect(result).to be_success

      expect(LlmConnection.active_connection.available_model_ids).to contain_exactly("qwen3.6-27b", "bge-m3")
    end
  end

  context "with another provider active" do
    let!(:connection) { create(:llm_connection, :with_models, base_url: "https://example.com/v1", api_key: "sk-original") }
    let!(:previous_provider) { connection.inference_provider }

    before do
      connection.update!(connection_fingerprint: connection.settings_fingerprint,
                         default_chat_model: connection.models.find_by!(external_id: "qwen3.6-27b"))
      create(:llm_model, :manual, llm_connection: connection, external_id: "hand-typed")
    end

    context "when the server answers" do
      let!(:models_request) do
        mock_llm_models_response(elsewhere, models: [{ id: "llama4-8b", object: "model", owned_by: "vllm" }])
      end

      it "points the connection at the provider" do
        expect(result).to be_success

        expect(connection.reload).to have_attributes(inference_provider: provider, api_key: "sk-elsewhere")
      end

      it "leaves the previous provider stored" do
        expect(result).to be_success

        expect(previous_provider.reload).to have_attributes(base_url: "https://example.com/v1", api_key: "sk-original")
      end

      it "requests the model list only for the refresh, without a probe before it" do
        expect(result).to be_success

        expect(models_request).to have_been_made.once
      end

      it "replaces the catalogue and keeps what an administrator entered" do
        expect(result).to be_success

        connection.reload
        expect(connection.available_model_ids).to contain_exactly("llama4-8b", "hand-typed")
        expect(connection).not_to be_models_stale
      end

      it "drops the default model of the previous server" do
        expect(result).to be_success

        expect(connection.reload.default_chat_model_id).to be_nil
      end

      it "reports no failed refresh" do
        expect(result.dependent_results).to all(be_success)
        expect(result.dependent_results).not_to be_empty
      end
    end

    context "when the server cannot be reached" do
      before { mock_llm_models_response(elsewhere, timeout: true) }

      it "switches anyway" do
        expect(result).to be_success

        expect(connection.reload.inference_provider).to eq(provider)
      end

      it "reports the failed refresh" do
        expect(result.dependent_results).to contain_exactly(be_failure)
      end

      it "discards what the previous server reported" do
        expect(result).to be_success

        connection.reload
        expect(connection.available_model_ids).to contain_exactly("hand-typed")
        expect(connection.default_chat_model_id).to be_nil
        expect(connection).to be_models_stale
      end
    end

    context "when the environment has written the connection" do
      before do
        mock_llm_models_response(elsewhere)
        connection.update_columns(env_provisioned_at: Time.current, env_fingerprint: "applied")
        allow(Setting).to receive(:llm_connection).and_return({ "base_url" => "https://example.com/v1" })
      end

      it "switches and lets go of the environment's marks" do
        expect(result).to be_success

        expect(connection.reload)
          .to have_attributes(inference_provider: provider, env_provisioned_at: nil, env_fingerprint: nil)
      end
    end
  end

  context "when switching back to a provider on the server it left" do
    let!(:connection) { create(:llm_connection, :with_models, base_url: "https://example.com/v1", api_key: "sk-original") }
    let(:provider) { connection.inference_provider }

    before do
      mock_llm_models_response("https://example.com/v1")
      mock_llm_models_response(elsewhere)
      described_class.new(user: create(:admin), model: create(:inference_provider, base_url: elsewhere)).call
    end

    it "needs nothing entered again" do
      expect(result).to be_success

      expect(connection.reload).to have_attributes(base_url: "https://example.com/v1", api_key: "sk-original")
      expect(connection.available_model_ids).to contain_exactly("qwen3.6-27b", "bge-m3")
    end
  end

  context "with the provider already active" do
    let!(:connection) { create(:llm_connection, base_url: elsewhere) }
    let(:provider) { connection.inference_provider }
    let!(:models_request) { mock_llm_models_response(elsewhere) }

    it "does not refresh the catalogue" do
      expect(result).to be_success

      expect(models_request).not_to have_been_made
    end
  end

  context "with another provider on the same server" do
    let!(:connection) { create(:llm_connection, :with_models, base_url: elsewhere, api_key: "sk-original") }
    let!(:models_request) { mock_llm_models_response(elsewhere) }

    before do
      connection.update!(connection_fingerprint: connection.settings_fingerprint,
                         default_chat_model: connection.models.find_by!(external_id: "qwen3.6-27b"))
    end

    it "keeps the catalogue and the default model" do
      expect(result).to be_success

      connection.reload
      expect(connection.api_key).to eq("sk-elsewhere")
      expect(connection.default_chat_model.external_id).to eq("qwen3.6-27b")
    end
  end
end
