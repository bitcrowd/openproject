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
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
#
# See COPYRIGHT and LICENSE files for more details.
#++

require "spec_helper"
require_module_spec_helper

RSpec.describe "Admin embedding sets", :skip_csrf,
               type: :rails_request, with_flag: { llm_connection: true, semantic_search: true },
               with_settings: { llm_features_enabled: true } do
  include_context "with an embedding model offered"

  shared_let(:admin) { create(:admin) }

  let(:turbo_headers) { { "Accept" => "text/vnd.turbo-stream.html" } }
  let(:valid_params) do
    { embedding_set: { title: "Nomic small", description: "Trial", model_id: "bge-m3",
                       embedding_vector_dimensions: 768, context_token_length: 2048 } }
  end

  before { login_as admin }

  describe "with the semantic search flag off", with_flag: { llm_connection: true, semantic_search: false } do
    it "does not expose the endpoints" do
      get new_dialog_embedding_sets_path
      expect(response).to have_http_status(:not_found)

      post embedding_sets_path, params: valid_params
      expect(response).to have_http_status(:not_found)
      expect(EmbeddingSet.count).to eq(0)
    end
  end

  describe "as a non-admin" do
    before { login_as create(:user) }

    it "refuses to create a set" do
      post embedding_sets_path, params: valid_params

      expect(response).to have_http_status(:forbidden)
      expect(EmbeddingSet.count).to eq(0)
    end
  end

  describe "GET /admin/llm_feature_bindings" do
    it "lists the embedding sets below the features" do
      create(:embedding_set, title: "Qwen3 baseline")

      get llm_feature_bindings_path

      expect(response).to have_http_status(:ok)
      expect(page).to have_test_selector("llm-embedding-set--box", text: "Qwen3 baseline")
      expect(page).to have_test_selector("llm-embedding-set--box", text: "Not ingested")
    end

    it "hides the box without the semantic search flag", with_flag: { llm_connection: true, semantic_search: false } do
      get llm_feature_bindings_path

      expect(page).to have_no_test_selector("llm-embedding-set--box")
    end
  end

  describe "GET new_dialog" do
    it "offers only embedding models" do
      get new_dialog_embedding_sets_path, headers: turbo_headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("New embedding set")

      items = Nokogiri::HTML(response.parsed_body).at_css("opce-autocompleter")["data-items"]
      expect(JSON.parse(items).pluck("id")).to contain_exactly("bge-m3")
    end
  end

  describe "POST /admin/embedding_sets" do
    it "creates the set and returns to the feature configuration" do
      post embedding_sets_path, params: valid_params

      expect(response).to redirect_to(llm_feature_bindings_path)
      expect(EmbeddingSet.sole).to have_attributes(title: "Nomic small", model_id: "bge-m3",
                                                   embedding_vector_dimensions: 768,
                                                   context_token_length: 2048, state: "created")
    end

    it "re-renders the form with errors" do
      post embedding_sets_path, params: { embedding_set: valid_params[:embedding_set].merge(model_id: "qwen3.6-27b") },
                                headers: turbo_headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("is not an embedding model offered by the configured LLM server.")
      expect(EmbeddingSet.count).to eq(0)
    end
  end

  describe "existing set" do
    let!(:embedding_set) { create(:embedding_set, title: "Qwen3 baseline") }

    it "renders the edit dialog" do
      get edit_dialog_embedding_set_path(embedding_set), headers: turbo_headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Edit &quot;Qwen3 baseline&quot;")
    end

    it "updates the set" do
      patch embedding_set_path(embedding_set),
            params: { embedding_set: { title: "Qwen3 production", context_token_length: 4096 } }

      expect(response).to redirect_to(llm_feature_bindings_path)
      expect(embedding_set.reload).to have_attributes(title: "Qwen3 production", context_token_length: 4096)
    end

    it "renders the deletion dialog" do
      get deletion_dialog_embedding_set_path(embedding_set), headers: turbo_headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Delete Qwen3 baseline?")
    end

    it "deletes the set" do
      delete embedding_set_path(embedding_set)

      expect(response).to redirect_to(llm_feature_bindings_path)
      expect(EmbeddingSet.count).to eq(0)
    end
  end
end
