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

  def default_chat_provider_picker
    find_test_selector("llm-connection--default-chat-provider")
  end

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
      click_on(label)
    end
  end

  context "when nothing is configured yet" do
    it "renders an accessible, empty settings page" do
      visit llm_connection_path

      check "Enable LLMs for this instance"

      expect(page).to have_field("Host URL")
      expect(page).to be_axe_clean
    end

    it "hides the server settings until the connection is enabled" do
      visit llm_connection_path

      expect(page).to have_field("Host URL", visible: :hidden)

      check "Enable LLMs for this instance"

      expect(page).to have_field("Host URL")
    end

    it "offers the models and feature tabs only once the connection is enabled" do
      mock_llm_models_response(base_url)

      visit llm_connection_path

      expect(page).to have_no_test_selector("llm-settings--tabs")

      check "Enable LLMs for this instance"
      fill_in "Host URL", with: base_url
      click_on "Save"

      expect(page).to have_test_selector("llm-settings--tabs")

      within_test_selector("llm-settings--tabs") { click_on "Models" }

      expect(page).to have_current_path(llm_models_path)

      within_test_selector("llm-settings--tabs") { click_on "Feature configuration" }

      expect(page).to have_current_path(llm_feature_bindings_path)
    end

    it "creates the provider and switches the features on with one save" do
      mock_llm_models_response(base_url)

      visit llm_connection_path

      check "Enable LLMs for this instance"
      fill_in "Host URL", with: base_url
      fill_in "API key", with: "sk-typed"
      click_on "Save"

      expect(page).to have_test_selector("llm-settings--tabs")
      expect(page).to have_no_field("Host URL")
      expect(InferenceProvider.sole).to have_attributes(title: "example.com", api_key: "sk-typed")
    end

    it "saves nothing when the server refuses, and keeps the form as it was" do
      mock_llm_models_response(base_url, response_code: 401)

      visit llm_connection_path

      check "Enable LLMs for this instance"
      fill_in "Host URL", with: base_url
      fill_in "API key", with: "sk-typed"
      click_on "Save"

      expect(page).to have_text("was rejected by the LLM server")
      expect(page).to have_checked_field("Enable LLMs for this instance")
      expect(page).to have_field("Host URL", with: base_url)
      expect(InferenceProvider.count).to eq(0)
    end

    it "describes the server the selected API format expects" do
      visit llm_connection_path

      check "Enable LLMs for this instance"

      expect(page).to have_text("speaks the OpenAI API")

      select "Anthropic", from: "API format"

      expect(page).to have_text("speaks the Anthropic API")
      expect(page).to have_no_text("speaks the OpenAI API")
    end
  end

  describe "the model list of each provider" do
    let!(:first) { create(:inference_provider, :with_models, title: "A first", base_url:) }
    let!(:second) { create(:inference_provider, title: "Elsewhere", base_url: "https://elsewhere.example/v1") }

    before do
      Setting.llm_features_enabled = true
      create(:llm_model, inference_provider: second, external_id: "llama4-8b")
      create(:llm_model, inference_provider: second, external_id: "mistral-7b")
    end

    def choose_provider(title)
      # The menu only opens once its element has been set up on the page.
      within_test_selector("llm-models--provider-select") do
        retry_block do
          find("button[aria-haspopup='true']").click
          click_link title
        end
      end
    end

    it "switches lists with the select, and stays there while working on the list" do
      visit llm_models_path

      expect(page).to have_text("qwen3.6-27b")
      expect(page).to have_no_text("llama4-8b")

      choose_provider "Elsewhere"

      expect(page).to have_current_path(llm_models_path(inference_provider_id: second.id))
      expect(page).to have_text("llama4-8b")
      expect(page).to have_no_text("qwen3.6-27b")
      expect(page).to be_axe_clean

      expand_sub_header_search("Filter models")
      fill_in "Filter models", with: "mistral"

      expect(page).to have_no_text("llama4-8b")
      expect(page).to have_text("mistral-7b")
      expect(page).to have_current_path(/inference_provider_id=#{second.id}/)

      find_test_selector("llm-model--add-button").click
      fill_in "Model name", with: "hand-typed"
      click_on "Create"

      expect(page).to have_current_path(llm_models_path(inference_provider_id: second.id))
      expect(second.models.manual.pluck(:external_id)).to eq(["hand-typed"])
      expect(first.models.manual).to be_empty
    end

    it "says that a provider has no list yet" do
      empty = create(:inference_provider, title: "Empty", base_url: "https://empty.example/v1")

      visit llm_models_path(inference_provider_id: empty.id)

      expect(page).to have_text("This provider has no model list yet.")
      expect(page).to be_axe_clean
    end
  end

  describe "the provider list" do
    let(:elsewhere) { "https://elsewhere.example/v1" }
    let!(:stored) { create(:inference_provider, title: "Stored", base_url: elsewhere, api_key: "sk-elsewhere") }

    before { Setting.llm_features_enabled = true }

    it "renders the new provider dialog accessibly" do
      visit llm_connection_path

      new_provider_dialog

      within_test_selector("llm-inference-provider-dialog") do
        expect(page).to be_axe_clean.skipping("color-contrast")
      end
    end

    it "adds a provider through the dialog" do
      mock_llm_models_response(base_url)

      visit llm_connection_path

      new_provider_dialog

      within_test_selector("llm-inference-provider-dialog") do
        fill_in "Display name", with: "Second"
        fill_in "Host URL", with: base_url
        find_test_selector("llm-inference-provider--submit").click
      end

      expect(page).to have_text(I18n.t(:notice_successful_create))
      expect(page).to have_test_selector("llm-inference-provider--row-#{InferenceProvider.find_by!(title: 'Second').id}")
    end

    it "shows a new provider's model check, then its health check, then the result",
       with_good_job_batches: [Llm::SyncModelsJob, Llm::DetectCapabilitiesJob, Llm::CheckProviderHealthJob] do
      mock_llm_models_response(base_url)
      mock_llm_embeddings_response(base_url)
      mock_llm_chat_response(base_url)

      visit llm_connection_path

      new_provider_dialog

      within_test_selector("llm-inference-provider-dialog") do
        fill_in "Display name", with: "Second"
        fill_in "Host URL", with: base_url
        find_test_selector("llm-inference-provider--submit").click
      end

      expect(page).to have_text(I18n.t(:notice_successful_create))
      second = InferenceProvider.find_by!(title: "Second")
      expect(page).to have_test_selector("llm-inference-provider--activity-#{second.id}", text: "Checking models…")

      GoodJob.perform_inline(limit: 2) # The fetch, then the capability detection.

      expect(page).to have_test_selector("llm-inference-provider--activity-#{second.id}", text: "Running checks…")

      GoodJob.perform_inline

      expect(page).to have_test_selector("llm-inference-provider--health-#{second.id}")
      expect(page).to have_no_test_selector("llm-inference-provider--activity-#{second.id}")
      expect(second.health_reports.count).to eq(1)
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
      expect(InferenceProvider.where(base_url:)).to be_empty
    end

    it "edits the title, with the server locked" do
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

    it "deletes the last provider and returns to the form" do
      visit llm_connection_path

      choose_row_action(stored, I18n.t("admin.inference_providers.menu.delete"))

      within_test_selector("llm-inference-provider--delete-dialog") do
        click_on I18n.t(:button_delete)
      end

      expect(page).to have_text(I18n.t(:notice_successful_delete))
      expect(page).to have_field("Host URL")
      expect(InferenceProvider.count).to eq(0)
    end

    it "says what keeps a provider in use from being deleted" do
      create(:semantic_index, title: "Docs", llm_model: create(:llm_model, inference_provider: stored, external_id: "bge-m3"))

      visit llm_connection_path

      choose_row_action(stored, I18n.t("admin.inference_providers.menu.delete"))

      within_test_selector("llm-inference-provider--delete-dialog") do
        expect(page).to have_text("Docs")
        expect(page).to have_text("bge-m3")
        expect(page).to have_no_button(I18n.t(:button_delete))
      end

      expect(InferenceProvider.exists?(stored.id)).to be(true)
    end
  end

  context "with a configured connection" do
    let!(:provider) { create(:inference_provider, :with_models, base_url:) }
    let(:connection) { LlmConnection.current }

    before do
      Setting.llm_features_enabled = true
      mock_llm_models_response(base_url)
    end

    it "renders the model list accessibly" do
      create(:llm_model,
             inference_provider: provider,
             external_id: "publisher/a-very-long-model-name-that-does-not-fit-the-column-32b-instruct-2026-05")

      visit llm_models_path

      expect(page).to have_test_selector("llm-model--refresh-button")
      expect(page).to have_text(provider.models.first.external_id)
      expect(page).to have_test_selector("llm-model--edit-#{provider.models.first.id}")
      expect(page).to be_axe_clean
    end

    it "picks and saves the default chat model" do
      visit llm_models_path

      expect(page).to have_test_selector("llm-connection--default-chat-provider")
      expect(page).to have_no_css("opce-autocompleter[data-input-name*='default_chat_model_id']")

      select_autocomplete(default_chat_provider_picker, query: provider.title, select_text: provider.title)

      expect(default_chat_model_picker).to have_css("input:focus")
      expect(page).to be_axe_clean

      select_autocomplete(default_chat_model_picker, query: "qwen", select_text: "qwen3.6-27b")
      within_test_selector("llm-connection--defaults-form") { click_on "Save" }

      expect(page).to have_text(I18n.t("admin.llm_models.defaults.success"))
      expect(connection.reload.default_chat_model.external_id).to eq("qwen3.6-27b")
      expect_current_autocompleter_value(default_chat_provider_picker, provider.title)
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

      expect(page).to have_current_path(llm_models_path(inference_provider_id: provider.id))
      expect(page).to have_text("nomic-embed-text")
      expect(provider.models.find_by(external_id: "nomic-embed-text")).to be_embedding
    end

    describe "the health report" do
      before { mock_llm_chat_response(base_url) }

      it "runs in the background from the row of the provider, and shows the result there with its time",
         with_good_job_batches: [Llm::CheckProviderHealthJob] do
        visit llm_connection_path

        choose_row_action(provider, I18n.t("admin.inference_providers.menu.run_health_check"))

        within_test_selector("llm-inference-provider--row-#{provider.id}") do
          expect(page).to have_test_selector("llm-inference-provider--activity-#{provider.id}", text: "Running checks…")
        end

        GoodJob.perform_inline

        within_test_selector("llm-inference-provider--row-#{provider.id}") do
          expect(page).to have_test_selector("llm-inference-provider--health-#{provider.id}")
          expect(page).to have_test_selector("llm-inference-provider--checked-at-#{provider.id}", text: /\d{2}:\d{2}\z/)
          expect(page).to have_no_test_selector("llm-inference-provider--activity-#{provider.id}")
        end
        expect(page).to have_current_path(llm_connection_path)
        expect(provider.health_reports.count).to eq(1)

        find_test_selector("llm-inference-provider--checked-at-#{provider.id}").click

        expect(page).to have_current_path(inference_provider_health_status_report_path(provider))
        expect(page).to have_text("Configuration")
      end

      it "runs the checks and renders the report accessibly" do
        visit inference_provider_health_status_report_path(provider)

        click_on "Run checks"

        expect(page).to have_text(/The checks have run: \d+ passed/)
        wait_for { provider.health_reports.count }.to eq(1)

        visit inference_provider_health_status_report_path(provider)

        expect(page).to have_text("Configuration")
        expect(page).to be_axe_clean

        find_test_selector("llm-connection--rerun-health-checks").click

        expect(page).to have_text(/The checks have run: \d+ passed/)
        expect(provider.health_reports.count).to eq(2)
      end
    end
  end
end
