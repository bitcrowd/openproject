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

# :selenium is required, not incidental: axe-core-api drives the browser through
# Selenium's #manage API, so be_axe_clean does not work under cuprite.
RSpec.describe "LLM connection administration",
               :js, :llm_server_helpers, :selenium, :webmock,
               driver: :firefox_de,
               with_flag: { llm_connection: true } do
  include Components::Autocompleter::NgSelectAutocompleteHelpers

  shared_let(:admin) { create(:admin) }

  let(:base_url) { "https://example.com/v1" }

  current_user { admin }

  def default_chat_model_picker
    find("[data-test-selector='llm-connection--defaults-form'] " \
         "opce-autocompleter[data-input-name*='default_chat_model_id']")
  end

  def new_provider_dialog
    find_test_selector("llm-inference-provider--new-button").click
    expect(page).to have_test_selector("llm-inference-provider-dialog")
  end

  def choose_row_action(provider, label)
    within_test_selector("llm-inference-provider--menu-#{provider.id}") do
      find("button[aria-haspopup='true']").click
      click_link(label)
    end
  end

  # The menu only opens once its element has been set up on the page.
  def choose_embedding_model_action(embedding_model, label)
    within_test_selector("llm-embedding-model--menu-#{embedding_model.id}") do
      retry_block do
        find("button[aria-haspopup='true']").click
        click_link(label)
      end
    end
  end

  context "when nothing is configured yet" do
    it "renders an accessible page with only the features switch" do
      visit llm_connection_path

      expect(page).to have_field("Enable LLMs for this instance", disabled: false)
      expect(page).to have_no_test_selector("llm-inference-provider--new-button")
      expect(page).to be_axe_clean
    end

    it "switches the features on, then creates the first provider, which becomes active" do
      mock_llm_models_response(base_url)

      visit llm_connection_path

      expect(page).to have_no_test_selector("llm-settings--tabs")

      check "Enable LLMs for this instance"
      within_test_selector("llm-connection--form") { click_on "Save" }

      expect(page).to have_test_selector("llm-inference-provider--new-button")
      expect(page).to have_no_test_selector("llm-settings--tabs")

      new_provider_dialog

      fill_in "Host URL", with: base_url
      fill_in "API key", with: "sk-typed"
      find_test_selector("llm-inference-provider--submit").click

      expect(page).to have_test_selector("llm-inference-provider--active-label")
      expect(page).to have_text("example.com")
      expect(page).to have_test_selector("llm-settings--tabs")

      within_test_selector("llm-settings--tabs") { click_on "Models" }

      expect(page).to have_current_path(llm_models_path)

      within_test_selector("llm-settings--tabs") { click_on "Feature configuration" }

      expect(page).to have_current_path(llm_feature_bindings_path)
    end

    context "with the features switched on" do
      before { Setting.llm_features_enabled = true }

      it "renders the new provider dialog accessibly" do
        visit llm_connection_path

        new_provider_dialog

        within_test_selector("llm-inference-provider-dialog") do
          expect(page).to be_axe_clean.skipping("color-contrast")
        end
      end

      it "describes the server the selected API format expects" do
        visit llm_connection_path

        new_provider_dialog

        expect(page).to have_text("speaks the OpenAI API")

        select "Anthropic", from: "API format"

        expect(page).to have_text("speaks the Anthropic API")
        expect(page).to have_no_text("speaks the OpenAI API")
      end

      it "keeps the dialog open with the reason when the server refuses" do
        mock_llm_models_response(base_url, response_code: 401)

        visit llm_connection_path

        new_provider_dialog

        fill_in "Host URL", with: base_url
        fill_in "API key", with: "sk-typed"
        find_test_selector("llm-inference-provider--submit").click

        within_test_selector("llm-inference-provider-dialog") do
          expect(page).to have_text("was rejected by the LLM server.")
          expect(page).to have_field("API key", with: "")
        end
        expect(InferenceProvider.count).to eq(0)
      end
    end
  end

  context "with a second provider stored" do
    let!(:connection) { create(:llm_connection, :with_models, base_url:, api_key: "sk-original") }
    let!(:stored) { create(:inference_provider, title: "Elsewhere", base_url: elsewhere, api_key: "sk-elsewhere") }
    let(:elsewhere) { "https://elsewhere.example/v1" }

    before do
      Setting.llm_features_enabled = true
      mock_llm_models_response(base_url)
      mock_llm_models_response(elsewhere)
    end

    it "switches to it and back without entering anything again" do
      visit llm_connection_path

      find_test_selector("llm-inference-provider--activate-#{stored.id}").click

      within_test_selector("llm-inference-provider-activate-dialog") do
        expect(page).to be_axe_clean.skipping("color-contrast")
        find_test_selector("llm-inference-provider--activate-submit").click
      end

      expect(page).to have_text(I18n.t("admin.inference_providers.activate.success", title: "Elsewhere"))
      expect(connection.reload.api_key).to eq("sk-elsewhere")

      previous = InferenceProvider.where.not(id: stored.id).first
      find_test_selector("llm-inference-provider--activate-#{previous.id}").click
      find_test_selector("llm-inference-provider--activate-submit").click

      expect(page).to have_text(I18n.t("admin.inference_providers.activate.success", title: previous.title))
      expect(connection.reload).to have_attributes(base_url:, api_key: "sk-original")
    end

    it "edits the title and key, with the server locked" do
      visit llm_connection_path

      choose_row_action(stored, I18n.t(:button_edit))

      within_test_selector("llm-inference-provider-dialog") do
        expect(page).to have_field("Host URL", disabled: true, with: elsewhere)
        expect(page).to have_field("API key", placeholder: "API key stored", with: "")
        fill_in "Display name", with: "Renamed"
        find_test_selector("llm-inference-provider--submit").click
      end

      expect(page).to have_text("Renamed")
      expect(stored.reload.api_key).to eq("sk-elsewhere")
    end

    it "removes the key of a provider, keeping the provider" do
      visit llm_connection_path

      choose_row_action(stored, I18n.t("admin.inference_providers.delete_api_key.menu_label"))

      within_test_selector("llm-inference-provider--delete-api-key-dialog") do
        # The muted description and the danger button label Primer renders around
        # our content miss the 4.5:1 contrast ratio, app-wide.
        expect(page).to be_axe_clean.skipping("color-contrast")
        click_on I18n.t("admin.inference_providers.delete_api_key.title")
      end

      expect(page).to have_text(I18n.t("admin.inference_providers.delete_api_key.success"))
      expect(stored.reload).to have_attributes(api_key: nil, base_url: elsewhere)
    end

    it "deletes a provider that is not active" do
      visit llm_connection_path

      choose_row_action(stored, I18n.t("admin.inference_providers.menu.delete"))

      within_test_selector("llm-inference-provider--delete-dialog") do
        click_on I18n.t(:button_delete)
      end

      expect(page).to have_text(I18n.t(:notice_successful_delete))
      expect(InferenceProvider.exists?(stored.id)).to be(false)
    end
  end

  context "with a configured connection" do
    let!(:connection) { create(:llm_connection, :with_models, base_url:) }

    before do
      Setting.llm_features_enabled = true
      mock_llm_models_response(base_url)
    end

    describe "storing an embedding model", with_flag: { llm_connection: true, semantic_search: true } do
      let(:llm_model) { connection.models.find_by!(external_id: "bge-m3") }

      before do
        create(:llm_capability_verdict, llm_connection: connection, model_id: "bge-m3",
                                        detail: { "dimensions" => 1024 })
      end

      it "stores it from its row, prefilled, and lists it accessibly" do
        visit llm_models_path

        expect(page).to have_text("No embedding model stored yet")

        find_test_selector("llm-model--store-#{llm_model.id}").click

        within_test_selector("llm-embedding-model-dialog") do
          expect(page).to have_field("Context length", with: "8192")
          expect(page).to have_field("Dimensions", with: "1024")
          expect(page).to have_select("Model type", selected: "Embedding model")
          expect(page).to be_axe_clean.skipping("color-contrast")

          find_test_selector("llm-embedding-model--submit").click
        end

        expect(page).to have_text(I18n.t(:notice_successful_create))

        stored = EmbeddingModel.sole
        expect(page).to have_test_selector("llm-embedding-model--row-#{stored.id}",
                                           text: "bge-m3 @ #{connection.inference_provider.title}")

        visit llm_models_path

        expect(page).to have_test_selector("llm-embedding-model--row-#{stored.id}")
        expect(page).to be_axe_clean
      end

      it "stores a model labeled as a chat model once the type is changed, and leaves its row as it is" do
        chat_model = connection.models.find_by!(external_id: "qwen3.6-27b")

        visit llm_models_path

        find_test_selector("llm-model--store-#{chat_model.id}").click

        within_test_selector("llm-embedding-model-dialog") do
          expect(page).to have_select("Model type", selected: "Chat model")
          expect(page).to have_text(I18n.t("admin.embedding_models.form.off_label_warning"))
          expect(page).to be_axe_clean.skipping("color-contrast")

          fill_in "Dimensions", with: "1024"
          find_test_selector("llm-embedding-model--submit").click

          expect(page).to have_text("Storing chat models in the collection is currently not supported.")

          select "Embedding model", from: "Model type"
          find_test_selector("llm-embedding-model--submit").click
        end

        expect(page).to have_text(I18n.t(:notice_successful_create))

        stored = EmbeddingModel.sole
        expect(page).to have_test_selector("llm-embedding-model--row-#{stored.id}",
                                           text: "qwen3.6-27b @ #{connection.inference_provider.title}")
        expect(find_test_selector("llm-model--store-#{chat_model.id}").ancestor("[role='row']"))
          .to have_css(".Label", exact_text: "Chat")
      end

      it "creates a semantic index from a stored model with its numbers prefilled, and re-points it once indexed" do
        create(:embedding_model, name: "First", inference_provider: create(:inference_provider, title: "One"),
                                 context_token_length: 2048, embedding_vector_dimensions: 768)
        create(:embedding_model, name: "Second", inference_provider: create(:inference_provider, title: "Two"),
                                 context_token_length: 512, embedding_vector_dimensions: 384)

        visit llm_feature_bindings_path

        find_test_selector("llm-semantic-index--new-button").click

        within_test_selector("llm-semantic-index-dialog") do
          fill_in "Display name", with: "My index"
          select "First @ One", from: "Model"

          expect(page).to have_field("Context length", with: "2048")
          expect(page).to have_field("Dimensions", with: "768")

          select "Second @ Two", from: "Model"

          expect(page).to have_field("Context length", with: "512")
          expect(page).to have_field("Dimensions", with: "384")
          expect(page).to be_axe_clean.skipping("color-contrast")

          find_test_selector("llm-semantic-index--submit").click
        end

        expect(page).to have_text(I18n.t(:notice_successful_create))

        semantic_index = SemanticIndex.sole
        expect(page).to have_test_selector("llm-semantic-index--row-#{semantic_index.id}", text: "Second")

        semantic_index.update!(state: "ready")
        visit llm_feature_bindings_path

        within_test_selector("llm-semantic-index--menu-#{semantic_index.id}") do
          retry_block do
            find("button[aria-haspopup='true']").click
            click_link(I18n.t(:button_edit))
          end
        end

        within_test_selector("llm-semantic-index-dialog") do
          expect(page).to have_text("Only use a model compatible with Second @ Two")
          expect(page).to have_field("Dimensions", disabled: true)

          select "First @ One", from: "Model"

          expect(page).to have_field("Dimensions", disabled: true, with: "384")

          find_test_selector("llm-semantic-index--submit").click
        end

        expect(page).to have_test_selector("llm-semantic-index--row-#{semantic_index.id}", text: "First")
        expect(semantic_index.reload).to have_attributes(state: "ready", embedding_vector_dimensions: 384)
      end

      it "renames it and deletes it" do
        stored = create(:embedding_model, inference_provider: connection.inference_provider, name: "Original")

        visit llm_models_path

        choose_embedding_model_action(stored, I18n.t(:button_edit))

        within_test_selector("llm-embedding-model-dialog") do
          expect(page).to have_field("Dimensions", disabled: true)

          fill_in "Display name", with: "Renamed"
          find_test_selector("llm-embedding-model--submit").click
        end

        expect(page).to have_test_selector("llm-embedding-model--row-#{stored.id}", text: "Renamed")

        choose_embedding_model_action(stored, I18n.t("admin.embedding_models.menu.delete"))

        within_test_selector("llm-embedding-model--delete-dialog") { click_on I18n.t(:button_delete) }

        expect(page).to have_no_test_selector("llm-embedding-model--row-#{stored.id}")
        expect(EmbeddingModel.exists?(stored.id)).to be(false)
      end
    end

    it "renders the model list accessibly" do
      create(:llm_model,
             llm_connection: connection,
             external_id: "publisher/a-very-long-model-name-that-does-not-fit-the-column-32b-instruct-2026-05")

      visit llm_models_path

      expect(page).to have_test_selector("llm-model--refresh-button")
      expect(page).to have_text(connection.models.first.external_id)
      expect(page).to have_test_selector("llm-model--edit-#{connection.models.first.id}")
      expect(page).to be_axe_clean
    end

    it "picks and saves the default chat model" do
      visit llm_models_path

      select_autocomplete(default_chat_model_picker, query: "qwen", select_text: "qwen3.6-27b")
      within_test_selector("llm-connection--defaults-form") { click_on "Save" }

      expect(page).to have_text(I18n.t("admin.llm_models.defaults.success"))
      expect(connection.reload.default_chat_model.external_id).to eq("qwen3.6-27b")
      expect_current_autocompleter_value(default_chat_model_picker, "qwen3.6-27b")
    end

    # The chat capabilities are hidden client-side, so only a browser shows that
    # the type choice actually reaches them.
    it "adds a model by hand and offers the capabilities its type can have" do
      visit llm_models_path
      expect(page).to have_test_selector("llm-model--refresh-button")

      find_test_selector("llm-model--add-button").click

      expect(page).to have_field("Model name")
      expect(page).to be_axe_clean
      expect(page).to have_field("Tool calling")

      fill_in "Model name", with: "nomic-embed-text"
      select "Embedding model", from: "Model type"

      expect(page).to have_field("Tool calling", visible: :hidden)

      click_on "Create"

      expect(page).to have_current_path(llm_models_path)
      expect(page).to have_text("nomic-embed-text")
      expect(connection.models.find_by(external_id: "nomic-embed-text")).to be_embedding
    end

    describe "the health report" do
      before { mock_llm_chat_response(base_url) }

      it "runs the checks and renders the report accessibly" do
        visit llm_connection_path

        find_test_selector("llm-connection--run-health-checks").click

        expect(page).to have_text("The checks have run.")
        wait_for { connection.health_reports.count }.to eq(1)

        find_test_selector("llm-connection--open-health-report").click

        expect(page).to have_current_path(llm_connection_health_status_report_path)
        expect(page).to have_text("Configuration")
        expect(page).to be_axe_clean

        find_test_selector("llm-connection--rerun-health-checks").click

        expect(page).to have_text(/The checks have run: \d+ passed/)
        expect(connection.health_reports.count).to eq(2)
      end
    end
  end
end
