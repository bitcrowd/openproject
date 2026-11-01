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

RSpec.describe "Admin embedding models", :llm_server_helpers, :skip_csrf, :webmock,
               type: :rails_request, with_flag: { llm_connection: true, semantic_search: true },
               with_settings: { llm_features_enabled: true } do
  include_context "with an embedding model offered"

  shared_let(:admin) { create(:admin) }

  let(:turbo_headers) { { "Accept" => "text/vnd.turbo-stream.html" } }
  let(:provider) { connection.inference_provider }
  let(:llm_model) { connection.models.find_by!(external_id: "bge-m3") }
  let(:chat_model) { connection.models.find_by!(external_id: "qwen3.6-27b") }
  let(:valid_params) do
    { embedding_model: { name: "", context_token_length: 8192, embedding_vector_dimensions: 1024 } }
  end

  def store_button_for(model) = "[data-test-selector='llm-model--store-#{model.id}']"

  before { login_as admin }

  shared_examples "refused endpoints" do |status|
    let!(:stored) { create(:embedding_model, name: "Original") }

    it "does not expose them" do
      get new_dialog_embedding_models_path(llm_model_id: llm_model.id), headers: turbo_headers
      expect(response).to have_http_status(status)

      post embedding_models_path(llm_model_id: llm_model.id), params: valid_params
      expect(response).to have_http_status(status)
      expect(EmbeddingModel.count).to eq(1)

      patch embedding_model_path(stored), params: { embedding_model: { name: "Renamed" } }
      expect(response).to have_http_status(status)
      expect(stored.reload.name).to eq("Original")

      delete embedding_model_path(stored)
      expect(response).to have_http_status(status)
      expect(EmbeddingModel.exists?(stored.id)).to be(true)
    end
  end

  describe "with the LLM connection flag off", with_flag: { llm_connection: false, semantic_search: true } do
    it_behaves_like "refused endpoints", :not_found
  end

  describe "with the semantic search flag off", with_flag: { llm_connection: true, semantic_search: false } do
    it_behaves_like "refused endpoints", :not_found

    it "offers nothing on the models page" do
      get llm_models_path

      expect(page).to have_no_css("[data-test-selector='llm-embedding-model--box']")
      expect(page).to have_no_css(store_button_for(llm_model))
    end
  end

  describe "as a non-admin" do
    before { login_as create(:user) }

    it_behaves_like "refused endpoints", :forbidden
  end

  describe "with the features switched off", with_settings: { llm_features_enabled: false } do
    it_behaves_like "refused endpoints", :see_other
  end

  describe "the models page" do
    it "lists stored models with their provider" do
      create(:embedding_model, inference_provider: provider, name: "Stored", external_id: "bge-m3")

      get llm_models_path

      within_box = page.find("[data-test-selector='llm-embedding-model--box']")
      expect(within_box).to have_text("Stored")
      expect(within_box).to have_text("bge-m3")
      expect(within_box).to have_text(provider.title)
    end

    it "says how to store one while there are none" do
      get llm_models_path

      expect(page).to have_text("No embedding model stored yet")
    end

    it "offers to store a model labeled as an embedding model" do
      get llm_models_path

      expect(page).to have_css(store_button_for(llm_model), text: "Use in collection")
    end

    it "does not offer to store a chat model" do
      get llm_models_path

      expect(page).to have_no_css(store_button_for(chat_model))
    end

    it "does not offer to store a model the server stopped offering" do
      llm_model.update!(active: false)

      get llm_models_path

      expect(page).to have_no_css(store_button_for(llm_model))
    end

    it "keeps offering it once stored, since other parameters make another embedding model" do
      create(:embedding_model, inference_provider: provider, external_id: "bge-m3")

      get llm_models_path

      expect(page).to have_css(store_button_for(llm_model))
    end
  end

  describe "GET new_dialog" do
    it "prefills what the list knows about the model" do
      connection.capability_verdicts.find_by!(model_id: "bge-m3").update!(detail: { "dimensions" => 768 })

      get new_dialog_embedding_models_path(llm_model_id: llm_model.id), headers: turbo_headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('value="8192"', 'value="768"', 'value="bge-m3"',
                                       "value=\"#{provider.title}\"")
    end

    it "leaves unknown values for the administrator to enter" do
      llm_model.update!(raw_metadata: {})

      get new_dialog_embedding_models_path(llm_model_id: llm_model.id), headers: turbo_headers

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('value="8192"')
    end

    it "does not offer a chat model" do
      get new_dialog_embedding_models_path(llm_model_id: chat_model.id), headers: turbo_headers

      expect(response).to have_http_status(:not_found)
    end

    it "escapes the provider's title" do
      provider.update!(title: "<script>provider</script>")

      get new_dialog_embedding_models_path(llm_model_id: llm_model.id), headers: turbo_headers

      expect(response.body).not_to include("<script>provider")
    end
  end

  describe "POST /admin/embedding_models" do
    it "stores the model with the active provider and names it after both" do
      post embedding_models_path(llm_model_id: llm_model.id), params: valid_params

      expect(response).to redirect_to(llm_models_path)
      expect(flash[:notice]).to eq(I18n.t(:notice_successful_create))
      expect(EmbeddingModel.sole)
        .to have_attributes(inference_provider: provider, external_id: "bge-m3",
                            name: "bge-m3 @ #{provider.title}",
                            context_token_length: 8192, embedding_vector_dimensions: 1024)
    end

    it "keeps a name the administrator entered" do
      post embedding_models_path(llm_model_id: llm_model.id),
           params: { embedding_model: valid_params[:embedding_model].merge(name: "Our embeddings") }

      expect(EmbeddingModel.sole.name).to eq("Our embeddings")
    end

    it "takes the model and the provider from the list, not from the request" do
      other_provider = create(:inference_provider)

      post embedding_models_path(llm_model_id: llm_model.id),
           params: { embedding_model: valid_params[:embedding_model]
                                        .merge(external_id: "forged", inference_provider_id: other_provider.id) }

      expect(EmbeddingModel.sole).to have_attributes(external_id: "bge-m3", inference_provider: provider)
    end

    it "refuses a model the active provider does not offer as an embedding model" do
      post embedding_models_path(llm_model_id: chat_model.id), params: valid_params

      expect(response).to have_http_status(:not_found)
      expect(EmbeddingModel.count).to eq(0)
    end

    it "keeps the dialog open when a parameter is missing" do
      post embedding_models_path(llm_model_id: llm_model.id),
           params: { embedding_model: { name: "", context_token_length: "", embedding_vector_dimensions: 1024 } },
           headers: turbo_headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(EmbeddingModel.count).to eq(0)
    end

    it "refuses an exact duplicate on the same provider and says why" do
      create(:embedding_model, inference_provider: provider, external_id: "bge-m3",
                               context_token_length: 8192, embedding_vector_dimensions: 1024)

      post embedding_models_path(llm_model_id: llm_model.id), params: valid_params, headers: turbo_headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("is already stored")
      expect(EmbeddingModel.count).to eq(1)
    end

    it "accepts other parameters for a model already stored" do
      create(:embedding_model, inference_provider: provider, external_id: "bge-m3",
                               context_token_length: 8192, embedding_vector_dimensions: 512)

      post embedding_models_path(llm_model_id: llm_model.id), params: valid_params

      expect(EmbeddingModel.count).to eq(2)
    end

    it "accepts the same model from a second provider" do
      create(:embedding_model, inference_provider: create(:inference_provider), external_id: "bge-m3",
                               context_token_length: 8192, embedding_vector_dimensions: 1024)

      post embedding_models_path(llm_model_id: llm_model.id), params: valid_params

      expect(EmbeddingModel.where(external_id: "bge-m3").count).to eq(2)
    end
  end

  describe "switching the active provider" do
    let(:elsewhere) { "https://elsewhere.example/v1" }
    let(:other_provider) { create(:inference_provider, base_url: elsewhere) }

    before { mock_llm_models_response(elsewhere, models: [{ id: "llama4-8b", object: "model", owned_by: "vllm" }]) }

    it "leaves stored models alone, though the list they came from is discarded" do
      stored_with = provider
      connection.update!(connection_fingerprint: connection.settings_fingerprint)
      post embedding_models_path(llm_model_id: llm_model.id), params: valid_params

      post activate_inference_provider_path(other_provider)

      expect(connection.reload.available_model_ids).to contain_exactly("llama4-8b")
      expect(EmbeddingModel.sole).to have_attributes(inference_provider: stored_with, external_id: "bge-m3")
    end
  end

  describe "editing" do
    let!(:stored) do
      create(:embedding_model, inference_provider: provider, name: "Original", external_id: "bge-m3",
                               context_token_length: 8192, embedding_vector_dimensions: 1024)
    end

    it "renders the dialog with everything but the name locked" do
      get edit_dialog_embedding_model_path(stored), headers: turbo_headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Edit &quot;Original&quot;")
      expect(response.body.scan(/<input[^>]*disabled[^>]*>/).size).to eq(4)
    end

    it "changes the name" do
      patch embedding_model_path(stored), params: { embedding_model: { name: "Renamed" } }

      expect(response).to redirect_to(llm_models_path)
      expect(stored.reload.name).to eq("Renamed")
    end

    it "falls back to the default name when it is emptied" do
      patch embedding_model_path(stored), params: { embedding_model: { name: "" } }

      expect(stored.reload.name).to eq("bge-m3 @ #{provider.title}")
    end

    it "changes nothing else" do
      patch embedding_model_path(stored),
            params: { embedding_model: { name: "Renamed", external_id: "forged", context_token_length: 1,
                                         embedding_vector_dimensions: 1,
                                         inference_provider_id: create(:inference_provider).id } }

      expect(stored.reload)
        .to have_attributes(name: "Renamed", external_id: "bge-m3", context_token_length: 8192,
                            embedding_vector_dimensions: 1024, inference_provider: provider)
    end
  end

  describe "deleting" do
    let!(:stored) { create(:embedding_model, name: "Stored") }

    it "renders the confirmation" do
      get deletion_dialog_embedding_model_path(stored), headers: turbo_headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Delete Stored?")
    end

    it "deletes the stored model" do
      delete embedding_model_path(stored)

      expect(response).to redirect_to(llm_models_path)
      expect(flash[:notice]).to eq(I18n.t(:notice_successful_delete))
      expect(EmbeddingModel.exists?(stored.id)).to be(false)
    end
  end
end
