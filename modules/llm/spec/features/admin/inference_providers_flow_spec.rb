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
RSpec.describe "Setting up several inference providers",
               :js, :llm_server_helpers, :selenium, :webmock,
               driver: :firefox_de,
               with_flag: { llm_connection: true, semantic_search: true } do
  include Components::Autocompleter::NgSelectAutocompleteHelpers

  shared_let(:admin) { create(:admin) }

  let(:first_url) { "https://first.example/v1" }
  let(:second_url) { "https://second.example/v1" }

  current_user { admin }

  def fetch_list_in_the_background(title)
    provider = InferenceProvider.find_by!(title:)
    Llm::SyncModelsJob.perform_now(provider.id)
    provider
  end

  def choose_row_action(provider, label)
    within_test_selector("llm-inference-provider--menu-#{provider.id}") do
      find("button[aria-haspopup='true']").click
      click_on(label)
    end
  end

  def on_tab(label)
    within_test_selector("llm-settings--tabs") { click_on label }
  end

  def choose_model(provider_picker, provider_title, model_picker, model_name)
    select_autocomplete(find_test_selector(provider_picker), query: provider_title, select_text: provider_title)
    select_autocomplete(find_test_selector(model_picker), query: model_name, select_text: model_name)
  end

  before do
    mock_llm_models_response(first_url, models: [{ id: "qwen3.6-27b", object: "model", owned_by: "vllm" },
                                                 { id: "bge-m3", object: "model", owned_by: "vllm" }])
    mock_llm_models_response(second_url, models: [{ id: "llama4-8b", object: "model", owned_by: "vllm" }])
    mock_llm_chat_response(second_url)
  end

  it "takes an administrator from nothing to two providers in use, and back to nothing",
     with_good_job_batches: [Llm::CheckProviderHealthJob] do
    # The first provider comes with the switch, in one form.
    visit llm_connection_path

    expect(page).to have_no_test_selector("llm-settings--tabs")

    check "Enable LLMs for this instance"
    fill_in "Display name", with: "First"
    fill_in "Host URL", with: first_url
    click_on "Save"

    expect(page).to have_test_selector("llm-settings--tabs")

    first = InferenceProvider.find_by!(title: "First")
    expect(page).to have_test_selector("llm-inference-provider--row-#{first.id}")

    # The flash banner sits outside every landmark, which axe would report.
    visit llm_connection_path

    expect(page).to be_axe_clean

    # Further providers come through the dialog.
    find_test_selector("llm-inference-provider--new-button").click

    within_test_selector("llm-inference-provider-dialog") do
      fill_in "Display name", with: "Second"
      fill_in "Host URL", with: second_url
      find_test_selector("llm-inference-provider--submit").click
    end

    expect(page).to have_text(I18n.t(:notice_successful_create))

    second = InferenceProvider.find_by!(title: "Second")
    expect(page).to have_test_selector("llm-inference-provider--row-#{second.id}")

    fetch_list_in_the_background("First")
    fetch_list_in_the_background("Second")
    create(:llm_capability_verdict, inference_provider: first, model_id: "bge-m3", capability: "embeddings",
                                    state: "supported", source: "probe")

    # Each has its own list.
    on_tab "Models"

    expect(page).to have_text("qwen3.6-27b")
    expect(page).to have_no_text("llama4-8b")

    within_test_selector("llm-models--provider-select") do
      retry_block do
        find("button[aria-haspopup='true']").click
        click_link "Second"
      end
    end

    expect(page).to have_text("llama4-8b")
    expect(page).to have_no_text("qwen3.6-27b")

    # A feature uses one provider, and a semantic index the other.
    on_tab "Feature configuration"

    choose_model("llm-feature-binding--provider-description_assistant", "Second",
                 "llm-feature-binding--model-description_assistant", "llama4-8b")
    expect(page).to be_axe_clean
    find_test_selector("llm-feature-binding--submit-description_assistant").click

    expect(page).to have_text(I18n.t("admin.llm_feature_bindings.update.success", feature: "Description assistant"))
    expect(LlmFeatureBinding.find_by!(feature_key: "description_assistant").llm_model.inference_provider).to eq(second)

    find_test_selector("llm-semantic-index--new-button").click

    within_test_selector("llm-semantic-index-dialog") do
      fill_in "Display name", with: "Docs"
      select_autocomplete(find_test_selector("llm-semantic-index--model"), query: "bge", select_text: "bge-m3",
                                                                           results_selector: "#llm-semantic-index-dialog")
      fill_in "Context length", with: "8192"
      fill_in "Dimensions", with: "1024"
      find_test_selector("llm-semantic-index--submit").click
    end

    expect(page).to have_test_selector("llm-semantic-index--box", text: "Docs")
    expect(SemanticIndex.sole.llm_model.inference_provider).to eq(first)

    # What is in use can't be deleted, and the dialog says why.
    on_tab "Inference providers"

    choose_row_action(second, I18n.t("admin.inference_providers.menu.delete"))

    within_test_selector("llm-inference-provider--delete-dialog") do
      expect(page).to have_text("Description assistant")
      expect(page).to have_text("llama4-8b")
      expect(page).to have_no_button(I18n.t(:button_delete))
      expect(page).to be_axe_clean.skipping("color-contrast")
      click_on I18n.t(:button_close)
    end

    # The health check runs from the row in the background, and its result shows there.
    choose_row_action(second, I18n.t("admin.inference_providers.menu.run_health_check"))

    expect(page).to have_test_selector("llm-inference-provider--activity-#{second.id}", text: "Running checks…")

    GoodJob.perform_inline

    expect(page).to have_test_selector("llm-inference-provider--health-#{second.id}")
    expect(page).to have_current_path(llm_connection_path)

    # Moving what uses a provider away frees it.
    LlmFeatureBinding.destroy_all

    choose_row_action(second, I18n.t("admin.inference_providers.menu.delete"))

    within_test_selector("llm-inference-provider--delete-dialog") { click_on I18n.t(:button_delete) }

    expect(page).to have_text(I18n.t(:notice_successful_delete))
    expect(InferenceProvider.exists?(second.id)).to be(false)
    expect(page).to have_test_selector("llm-inference-provider--row-#{first.id}")

    SemanticIndex.destroy_all

    choose_row_action(first, I18n.t("admin.inference_providers.menu.delete"))

    within_test_selector("llm-inference-provider--delete-dialog") { click_on I18n.t(:button_delete) }

    # The last one gone, the page is back to the first form.
    expect(page).to have_field("Host URL")
    expect(page).to have_no_test_selector("llm-settings--tabs")
  end
end
