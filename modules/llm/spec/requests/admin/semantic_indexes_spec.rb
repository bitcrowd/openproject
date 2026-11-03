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

RSpec.describe "Admin semantic indexes", :skip_csrf,
               type: :rails_request, with_flag: { llm_connection: true, semantic_search: true },
               with_settings: { llm_features_enabled: true } do
  include_context "with an embedding model offered"

  shared_let(:admin) { create(:admin) }

  let(:turbo_headers) { { "Accept" => "text/vnd.turbo-stream.html" } }
  let(:embedding_model) { provider.models.find_by!(external_id: "bge-m3") }
  let(:chat_model) { provider.models.find_by!(external_id: "qwen3.6-27b") }
  let(:valid_params) do
    { semantic_index: { title: "Nomic small", description: "Trial", llm_model_id: embedding_model.id,
                        embedding_vector_dimensions: 768, context_token_length: 2048 } }
  end

  before { login_as admin }

  describe "with the semantic search flag off", with_flag: { llm_connection: true, semantic_search: false } do
    it "does not expose the endpoints" do
      get new_dialog_semantic_indexes_path
      expect(response).to have_http_status(:not_found)

      post semantic_indexes_path, params: valid_params
      expect(response).to have_http_status(:not_found)
      expect(SemanticIndex.count).to eq(0)
    end
  end

  describe "with the semantic search flag on but pgvector unavailable" do
    before { allow(OpenProject::Llm::Pgvector).to receive(:available?).and_return(false) }

    it "shows the box below the pgvector warning on the feature configuration" do
      create(:semantic_index, title: "Qwen3 baseline")

      get llm_feature_bindings_path

      expect(page).to have_test_selector("llm-feature-bindings--pgvector-unavailable")
      expect(page).to have_test_selector("llm-semantic-index--box", text: "Qwen3 baseline")
    end

    it "creates the semantic index" do
      post semantic_indexes_path, params: valid_params

      expect(response).to redirect_to(llm_feature_bindings_path)
      expect(SemanticIndex.sole).to have_attributes(title: "Nomic small", state: "not_indexed")
    end

    it "refuses to start indexing" do
      semantic_index = create(:semantic_index, title: "Qwen3 baseline")

      post start_indexing_semantic_index_path(semantic_index)

      expect(response).to redirect_to(llm_feature_bindings_path)
      expect(flash[:error]).to eq(I18n.t("admin.semantic_indexes.indexing.not_ready.pgvector_missing"))
      expect(semantic_index.reload).to be_not_indexed
      expect(GoodJob::Job.where(job_class: Llm::IndexWorkPackagesJob.name)).to be_empty
    end
  end

  describe "as a non-admin" do
    before { login_as create(:user) }

    it "refuses to create an semantic index" do
      post semantic_indexes_path, params: valid_params

      expect(response).to have_http_status(:forbidden)
      expect(SemanticIndex.count).to eq(0)
    end

    it "refuses to start indexing" do
      semantic_index = create(:semantic_index, state: "indexing")

      post start_indexing_semantic_index_path(semantic_index)

      expect(response).to have_http_status(:forbidden)
      expect(semantic_index.reload).to be_indexing
    end

    it "refuses to stop indexing" do
      semantic_index = create(:semantic_index, state: "indexing")

      post stop_indexing_semantic_index_path(semantic_index)

      expect(response).to have_http_status(:forbidden)
      expect(semantic_index.reload).to be_indexing
    end
  end

  describe "GET /admin/llm_feature_bindings" do
    it "lists the semantic indexes below the features" do
      create(:semantic_index, title: "Qwen3 baseline")

      get llm_feature_bindings_path

      expect(response).to have_http_status(:ok)
      expect(page).to have_test_selector("llm-semantic-index--box", text: "Qwen3 baseline")
      expect(page).to have_test_selector("llm-semantic-index--box",
                                         text: I18n.t("admin.semantic_indexes.states.not_indexed"))
      expect(page).to have_test_selector("llm-semantic-index--new-button")
    end

    it "shows an empty state while no semantic index exists" do
      get llm_feature_bindings_path

      expect(page).to have_test_selector("llm-semantic-index--box",
                                         text: I18n.t("admin.semantic_indexes.box.empty_title"))
      expect(page).to have_test_selector("llm-semantic-index--box",
                                         text: I18n.t("admin.semantic_indexes.box.empty_description"))
    end

    it "hides the box without the semantic search flag", with_flag: { llm_connection: true, semantic_search: false } do
      get llm_feature_bindings_path

      expect(page).to have_no_test_selector("llm-semantic-index--box")
    end
  end

  describe "GET new_dialog" do
    it "offers only embedding models" do
      get new_dialog_semantic_indexes_path, headers: turbo_headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("admin.semantic_indexes.dialog.new_title"))

      items = Nokogiri::HTML(response.parsed_body).at_css("[data-test-selector='llm-semantic-index--model']")["data-items"]
      expect(JSON.parse(items).pluck("name")).to contain_exactly("bge-m3")
    end
  end

  describe "POST refresh_form" do
    let(:refreshed) { Nokogiri::HTML(response.parsed_body) }

    def field_value(attribute)
      refreshed.at_css("input[name='semantic_index[#{attribute}]']")["value"]
    end

    before { embedding_model.update!(embedding_vector_dimensions: 1024) }

    it "fills in what the chosen model knows, without saving" do
      post refresh_form_semantic_indexes_path,
           params: { semantic_index: { title: "Docs", llm_model_id: embedding_model.id, prefilled_from_model_id: "",
                                       context_token_length: "", embedding_vector_dimensions: "" } },
           headers: turbo_headers

      expect(response).to have_http_status(:ok)
      expect(field_value(:title)).to eq("Docs")
      expect(field_value(:context_token_length)).to eq("8192")
      expect(field_value(:embedding_vector_dimensions)).to eq("1024")
      expect(field_value(:prefilled_from_model_id)).to eq(embedding_model.id.to_s)
      expect(SemanticIndex.count).to eq(0)
    end

    it "keeps a typed value" do
      post refresh_form_semantic_indexes_path,
           params: { semantic_index: { llm_model_id: embedding_model.id, prefilled_from_model_id: "",
                                       context_token_length: "", embedding_vector_dimensions: "512" } },
           headers: turbo_headers

      expect(field_value(:embedding_vector_dimensions)).to eq("512")
    end

    it "does not save an existing semantic index" do
      semantic_index = create(:semantic_index, title: "Qwen3 baseline")

      post refresh_form_semantic_index_path(semantic_index),
           params: { semantic_index: { title: "Changed", llm_model_id: embedding_model.id } },
           headers: turbo_headers

      expect(field_value(:title)).to eq("Changed")
      expect(semantic_index.reload.title).to eq("Qwen3 baseline")
    end

    context "with a second provider" do
      let!(:other_provider) { create(:inference_provider, title: "Z elsewhere", base_url: "https://elsewhere.example/v1") }
      let!(:other_model) do
        create(:llm_model, inference_provider: other_provider, external_id: "nomic-embed",
                           admin_context_window: 2048, embedding_vector_dimensions: 768)
      end

      def picker(field) = refreshed.at_css("[data-test-selector='llm-semantic-index--#{field}']")

      def offered_names(field) = JSON.parse(picker(field)["data-items"]).pluck("name")

      def selected(field) = JSON.parse(picker(field)["data-model"])&.fetch("id").presence

      def refresh(semantic_index: nil, **fields)
        path = semantic_index ? refresh_form_semantic_index_path(semantic_index) : refresh_form_semantic_indexes_path

        post path, params: { semantic_index: { title: "Docs", llm_model_id: "", prefilled_from_model_id: "", **fields } },
                   headers: turbo_headers
      end

      before do
        create(:llm_capability_verdict, inference_provider: other_provider, model_id: "nomic-embed",
                                        capability: "embeddings", state: "supported", source: "probe")
      end

      it "opens on the first provider by title, offering every one of them and no blank" do
        get new_dialog_semantic_indexes_path, headers: turbo_headers

        expect(offered_names(:provider)).to eq([provider.title, "Z elsewhere"])
        expect(selected(:provider)).to eq(provider.id)
        expect(offered_names(:model)).to eq(["bge-m3"])
      end

      it "offers the models of a picked provider" do
        refresh(provider_id: other_provider.id, context_token_length: "", embedding_vector_dimensions: "")

        expect(selected(:provider)).to eq(other_provider.id)
        expect(offered_names(:model)).to eq(["nomic-embed"])
        expect(selected(:model)).to be_nil
      end

      it "forgets a model of the provider left behind, with what it filled in, and keeps what was typed" do
        refresh(provider_id: other_provider.id, llm_model_id: embedding_model.id, prefilled_from_model_id: embedding_model.id,
                context_token_length: "8192", embedding_vector_dimensions: "512")

        expect(selected(:model)).to be_nil
        expect(field_value(:context_token_length)).to be_nil
        expect(field_value(:embedding_vector_dimensions)).to eq("512")
        expect(field_value(:prefilled_from_model_id)).to be_nil
      end

      it "fills in from the model chosen after that" do
        refresh(provider_id: other_provider.id, llm_model_id: other_model.id, prefilled_from_model_id: "",
                context_token_length: "", embedding_vector_dimensions: "512")

        expect(selected(:model)).to eq(other_model.id)
        expect(field_value(:context_token_length)).to eq("2048")
        expect(field_value(:embedding_vector_dimensions)).to eq("512")
        expect(field_value(:prefilled_from_model_id)).to eq(other_model.id.to_s)
      end

      it "stays on the picked provider when a save fails" do
        post semantic_indexes_path,
             params: { semantic_index: valid_params[:semantic_index].merge(llm_model_id: "", provider_id: other_provider.id) },
             headers: turbo_headers

        expect(response).to have_http_status(:unprocessable_entity)
        expect(selected(:provider)).to eq(other_provider.id)
        expect(offered_names(:model)).to eq(["nomic-embed"])
      end

      describe "an indexed semantic index" do
        let!(:semantic_index) do
          create(:semantic_index, title: "Docs", state: :ready, llm_model: embedding_model,
                                  context_token_length: 4096, embedding_vector_dimensions: 1536)
        end

        it "shows the models of another provider, keeping its numbers" do
          refresh(semantic_index:, provider_id: other_provider.id, llm_model_id: embedding_model.id)

          expect(offered_names(:model)).to eq(["nomic-embed"])
          expect(selected(:model)).to be_nil
          expect(field_value(:context_token_length)).to eq("4096")
          expect(field_value(:embedding_vector_dimensions)).to eq("1536")
          expect(semantic_index.reload.llm_model).to eq(embedding_model)
        end

        it "fills in nothing when a model is picked" do
          refresh(semantic_index:, provider_id: other_provider.id, llm_model_id: other_model.id)

          expect(selected(:model)).to eq(other_model.id)
          expect(field_value(:context_token_length)).to eq("4096")
          expect(field_value(:embedding_vector_dimensions)).to eq("1536")
        end

        it "moves to a model of another provider, keeping its numbers" do
          patch semantic_index_path(semantic_index),
                params: { semantic_index: { title: "Docs", provider_id: other_provider.id, llm_model_id: other_model.id } }

          expect(response).to redirect_to(llm_feature_bindings_path)
          expect(semantic_index.reload)
            .to have_attributes(llm_model: other_model, context_token_length: 4096, embedding_vector_dimensions: 1536)
        end
      end
    end

    it "is refused for a non-admin" do
      login_as create(:user)

      post refresh_form_semantic_indexes_path, params: valid_params, headers: turbo_headers

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "POST /admin/semantic_indexes" do
    it "creates the semantic index and returns to the feature configuration" do
      post semantic_indexes_path, params: valid_params

      expect(response).to redirect_to(llm_feature_bindings_path)
      expect(SemanticIndex.sole).to have_attributes(title: "Nomic small", llm_model: embedding_model,
                                                    embedding_vector_dimensions: 768,
                                                    context_token_length: 2048, state: "not_indexed")
    end

    it "re-renders the form with errors" do
      post semantic_indexes_path, params: { semantic_index: valid_params[:semantic_index].merge(llm_model_id: chat_model.id) },
                                  headers: turbo_headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include(I18n.t("activerecord.errors.models.semantic_index.attributes.llm_model_id.not_offered"))
      expect(SemanticIndex.count).to eq(0)
    end
  end

  describe "existing semantic index" do
    let!(:semantic_index) { create(:semantic_index, title: "Qwen3 baseline") }

    it "renders the edit dialog" do
      get edit_dialog_semantic_index_path(semantic_index), headers: turbo_headers

      expect(response).to have_http_status(:ok)
      expect(response.body)
        .to include(CGI.escapeHTML(I18n.t("admin.semantic_indexes.dialog.edit_title", title: semantic_index.title)))
    end

    it "locks the parameters in the edit dialog once indexed" do
      semantic_index.update!(state: "failed")

      get edit_dialog_semantic_index_path(semantic_index), headers: turbo_headers

      expect(response.body).to include(
        CGI.escapeHTML(I18n.t("admin.semantic_indexes.form.locked_once_indexed",
                              model: "bge-m3", context_token_length: 8192, embedding_vector_dimensions: 1024))
      )
    end

    it "moves an indexed semantic index to another embedding model, keeping its state" do
      other_model = create(:llm_model, inference_provider: provider, external_id: "bge-m3-elsewhere")
      provider.capability_verdicts.create!(model_id: other_model.external_id, capability: "embeddings",
                                           state: "supported", source: "probe", checked_at: Time.current)
      semantic_index.update!(state: "ready")

      patch semantic_index_path(semantic_index), params: { semantic_index: { llm_model_id: other_model.id } }

      expect(response).to redirect_to(llm_feature_bindings_path)
      expect(semantic_index.reload).to have_attributes(llm_model: other_model, state: "ready")
    end

    it "updates the semantic index" do
      patch semantic_index_path(semantic_index),
            params: { semantic_index: { title: "Qwen3 production", context_token_length: 4096 } }

      expect(response).to redirect_to(llm_feature_bindings_path)
      expect(semantic_index.reload).to have_attributes(title: "Qwen3 production", context_token_length: 4096)
    end

    it "renders the deletion dialog" do
      get deletion_dialog_semantic_index_path(semantic_index), headers: turbo_headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("admin.semantic_indexes.destroy.heading", title: semantic_index.title))
    end

    it "deletes the semantic index" do
      delete semantic_index_path(semantic_index)

      expect(response).to redirect_to(llm_feature_bindings_path)
      expect(SemanticIndex.count).to eq(0)
    end

    context "when indexing", with_good_job_batches: [Llm::IndexWorkPackagesJob] do
      def index_jobs = GoodJob::Job.where(job_class: Llm::IndexWorkPackagesJob.name)

      it "starts indexing" do
        post start_indexing_semantic_index_path(semantic_index)

        expect(response).to redirect_to(llm_feature_bindings_path)
        expect(flash[:notice]).to eq(I18n.t("admin.semantic_indexes.start_indexing.started", title: semantic_index.title))
        expect(semantic_index.reload).to be_indexing
        expect(index_jobs.pluck(:batch_id)).to eq([semantic_index.indexing_batch_id])
      end

      it "re-indexes a ready semantic index" do
        semantic_index.update!(state: "ready")

        post start_indexing_semantic_index_path(semantic_index)

        expect(semantic_index.reload).to be_indexing
        expect(index_jobs.count).to eq(1)
      end

      it "refuses to start indexing twice" do
        semantic_index.update!(state: "indexing")

        post start_indexing_semantic_index_path(semantic_index)

        expect(flash[:error]).to eq(I18n.t("admin.semantic_indexes.start_indexing.not_indexable"))
        expect(index_jobs).to be_empty
      end

      it "shows a stop button while indexing" do
        semantic_index.update!(state: "indexing")

        get llm_feature_bindings_path

        expect(page).to have_test_selector("llm-semantic-index--stop-indexing-#{semantic_index.id}")
        expect(page).to have_no_test_selector("llm-semantic-index--start-indexing-#{semantic_index.id}")
      end

      it "stops indexing and discards the queued jobs" do
        post start_indexing_semantic_index_path(semantic_index)
        batch_id = semantic_index.reload.indexing_batch_id
        expect(GoodJob::Job.where(batch_id:)).not_to be_empty

        post stop_indexing_semantic_index_path(semantic_index)

        expect(response).to redirect_to(llm_feature_bindings_path)
        expect(flash[:notice]).to eq(I18n.t("admin.semantic_indexes.stop_indexing.stopped", title: semantic_index.title))
        expect(semantic_index.reload).to be_not_indexed
        expect(GoodJob::Job.where(batch_id:).reload.map(&:status)).to all(eq(:discarded))
      end

      it "refuses to stop when not indexing" do
        post stop_indexing_semantic_index_path(semantic_index)

        expect(response).to redirect_to(llm_feature_bindings_path)
        expect(flash[:error]).to eq(I18n.t("admin.semantic_indexes.stop_indexing.not_indexing"))
        expect(semantic_index.reload).to be_not_indexed
      end
    end
  end

  describe "the list on the feature configuration page" do
    let!(:semantic_index) { create(:semantic_index, title: "Docs") }

    it "names the inference provider of each semantic index next to its model" do
      get llm_feature_bindings_path

      row = page.find("[data-test-selector='llm-semantic-index--row-#{semantic_index.id}']")
      expect(row).to have_text(semantic_index.llm_model.inference_provider.title)
      expect(row).to have_text(semantic_index.llm_model.external_id)
    end
  end

  describe "activation" do
    let!(:current) { create(:semantic_index, title: "Qwen3 baseline", state: "ready") }
    let!(:candidate) { create(:semantic_index, title: "Nomic small", state: "ready") }

    before { connection.feature_bindings.create!(feature_key: "semantic_search", semantic_index: current) }

    it "groups the active semantic index above the others" do
      get llm_feature_bindings_path

      rows = page.all("[data-test-selector^='llm-semantic-index--row-']")
      expect(rows.pluck("data-test-selector"))
        .to eq(["llm-semantic-index--row-#{current.id}", "llm-semantic-index--row-#{candidate.id}"])

      active_row = page.find("[data-test-selector='llm-semantic-index--row-#{current.id}']")
      expect(active_row).to have_test_selector("llm-semantic-index--active-label",
                                               text: I18n.t("admin.semantic_indexes.active"))
      expect(active_row).to have_text("Qwen3 baseline")
      expect(active_row).to have_no_test_selector("llm-semantic-index--activate-#{current.id}")

      candidate_row = page.find("[data-test-selector='llm-semantic-index--row-#{candidate.id}']")
      expect(candidate_row).to have_no_test_selector("llm-semantic-index--active-label")
      expect(candidate_row).to have_test_selector("llm-semantic-index--activate-#{candidate.id}")
    end

    it "names both Semantic Indexes in the confirmation dialog" do
      get activation_dialog_semantic_index_path(candidate), headers: turbo_headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("admin.semantic_indexes.activate.body_switch_html",
                                              current: current.title, title: candidate.title))
    end

    it "activates a ready semantic index" do
      post activate_semantic_index_path(candidate)

      expect(response).to redirect_to(llm_feature_bindings_path)
      expect(flash[:notice]).to eq(I18n.t("admin.semantic_indexes.activate.success", title: candidate.title))
      expect(SemanticIndex.semantic_search_binding.semantic_index).to eq(candidate)
    end

    it "refuses to delete the active semantic index" do
      delete semantic_index_path(current)

      expect(flash[:error]).to include(I18n.t("activerecord.errors.models.semantic_index.attributes.base.active"))
      expect(SemanticIndex.exists?(current.id)).to be(true)
    end
  end

  describe "GET status" do
    it "reports the progress of a semantic index that is indexing and keeps polling" do
      batch = GoodJob::Batch.new.tap(&:save)
      create(:semantic_index, state: "indexing", indexing_batch_id: batch.id)
      [Time.current, nil, nil, nil].each do |finished_at|
        GoodJob::Job.create!(id: SecureRandom.uuid, active_job_id: SecureRandom.uuid, batch_id: batch.id,
                             job_class: Llm::EmbedWorkPackagesJob.name, queue_name: "default",
                             serialized_params: {}, finished_at:)
      end

      get status_semantic_indexes_path, headers: turbo_headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("turbo-stream",
                                       I18n.t("admin.semantic_indexes.indexing.progress", percentage: 25),
                                       "poll-for-changes")
    end

    it "replaces the box once indexing has finished" do
      create(:semantic_index, state: "failed", error_message: "Some Error")

      get status_semantic_indexes_path, headers: turbo_headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("turbo-stream",
                                       I18n.t("admin.semantic_indexes.states.failed"),
                                       "Some Error")
    end
  end
end
