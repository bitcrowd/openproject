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

RSpec.describe "Admin inference providers", :llm_server_helpers, :skip_csrf, :webmock,
               type: :rails_request, with_flag: { llm_connection: true } do
  let(:admin) { create(:admin) }
  let(:turbo_headers) { { "Accept" => "text/vnd.turbo-stream.html" } }
  let(:base_url) { "https://example.com/v1" }
  let(:elsewhere) { "https://elsewhere.example/v1" }
  let(:new_provider_params) { { title: "Elsewhere", api_format: "openai", base_url: elsewhere, api_key: "sk-test" } }

  def row_for(provider)
    page.find("[data-test-selector='llm-inference-provider--row-#{provider.id}']")
  end

  def store_health_report(owner, **)
    group = HealthReport::ResultGroup.new(key: :configuration, results: [HealthReport::Result.success(:enabled)])
    owner.health_reports.create!(results: [group], **)
  end

  before do
    login_as admin
    Setting.llm_features_enabled = true
  end

  describe "with the features switched off" do
    let!(:provider) { create(:inference_provider, api_key: "sk-original", title: "Original") }

    before { Setting.llm_features_enabled = false }

    it "sends every endpoint back to the switch" do
      get new_dialog_inference_providers_path, headers: turbo_headers
      expect(response).to redirect_to(llm_connection_path)

      post inference_providers_path, params: { inference_provider: new_provider_params }
      expect(response).to redirect_to(llm_connection_path)
      expect(InferenceProvider.count).to eq(1)

      patch inference_provider_path(provider), params: { inference_provider: { title: "Renamed" } }
      expect(response).to redirect_to(llm_connection_path)
      expect(provider.reload.title).to eq("Original")

      post activate_inference_provider_path(provider)
      expect(response).to redirect_to(llm_connection_path)
      expect(LlmConnection.count).to eq(0)

      delete api_key_inference_provider_path(provider)
      expect(response).to redirect_to(llm_connection_path)
      expect(provider.reload.api_key).to eq("sk-original")

      delete inference_provider_path(provider)
      expect(response).to redirect_to(llm_connection_path)
      expect(flash[:notice]).to eq(I18n.t("admin.llm_connections.disabled_notice"))
      expect(InferenceProvider.exists?(provider.id)).to be(true)
    end
  end

  describe "with the feature flag off", with_flag: { llm_connection: false } do
    let!(:provider) { create(:inference_provider, api_key: "sk-original", title: "Original") }

    it "does not expose the endpoints" do
      get new_dialog_inference_providers_path, headers: turbo_headers
      expect(response).to have_http_status(:not_found)

      post inference_providers_path, params: { inference_provider: new_provider_params }
      expect(response).to have_http_status(:not_found)
      expect(InferenceProvider.count).to eq(1)

      patch inference_provider_path(provider), params: { inference_provider: { title: "Renamed" } }
      expect(response).to have_http_status(:not_found)
      expect(provider.reload.title).to eq("Original")

      post activate_inference_provider_path(provider)
      expect(response).to have_http_status(:not_found)
      expect(LlmConnection.count).to eq(0)

      delete api_key_inference_provider_path(provider)
      expect(response).to have_http_status(:not_found)
      expect(provider.reload.api_key).to eq("sk-original")

      delete inference_provider_path(provider)
      expect(response).to have_http_status(:not_found)
      expect(InferenceProvider.exists?(provider.id)).to be(true)
    end
  end

  describe "as a non-admin" do
    let!(:connection) { create(:llm_connection, base_url:, api_key: "sk-original") }
    let!(:provider) { create(:inference_provider, api_key: "sk-stored", title: "Stored") }

    before { login_as create(:user) }

    it "refuses every endpoint" do
      get new_dialog_inference_providers_path, headers: turbo_headers
      expect(response).to have_http_status(:forbidden)

      post inference_providers_path, params: { inference_provider: new_provider_params }
      expect(response).to have_http_status(:forbidden)
      expect(InferenceProvider.count).to eq(2)

      patch inference_provider_path(provider), params: { inference_provider: { api_key: "sk-stolen" } }
      expect(response).to have_http_status(:forbidden)
      expect(provider.reload.api_key).to eq("sk-stored")

      post activate_inference_provider_path(provider)
      expect(response).to have_http_status(:forbidden)
      expect(connection.reload.api_key).to eq("sk-original")

      delete api_key_inference_provider_path(provider)
      expect(response).to have_http_status(:forbidden)
      expect(provider.reload.api_key).to eq("sk-stored")

      delete inference_provider_path(provider)
      expect(response).to have_http_status(:forbidden)
      expect(InferenceProvider.exists?(provider.id)).to be(true)
    end
  end

  describe "the list on the connection page" do
    it "offers to add one when none is stored" do
      get llm_connection_path

      expect(response).to have_http_status(:ok)
      expect(page).to have_css("[data-test-selector='llm-inference-provider--new-button']")
      expect(page).to have_css("[data-test-selector='llm-inference-provider--box']", text: "No inference provider yet")
    end

    it "is there with the features switched off, since they need a provider first" do
      create(:llm_connection, base_url:)

      get llm_connection_path

      expect(page).to have_css("[data-test-selector='llm-inference-provider--new-button']")
    end

    it "shows the settings of a provider" do
      provider = create(:llm_connection, base_url:, api_key: "sk-test").inference_provider
      provider.update!(title: "My gateway")

      get llm_connection_path

      row = row_for(provider)
      expect(row).to have_text("My gateway")
      expect(row).to have_text(base_url)
      expect(row).to have_text("OpenAI")
      expect(row).to have_text("Stored")
    end

    it "says when a provider has no key" do
      provider = create(:inference_provider, api_key: nil)

      get llm_connection_path

      expect(row_for(provider)).to have_text("None")
    end

    it "does not show the key or anything else that can carry a credential" do
      create(:inference_provider, api_key: "sk-original",
                                  base_url: "https://user:url-password@example.com/v1?token=url-token",
                                  custom_headers: { "X-Gateway-Key" => "sk-header" })

      get llm_connection_path

      expect(response.body).not_to include("sk-original", "url-password", "url-token", "sk-header")
    end

    it "lists the active provider first and marks it" do
      stored = create(:inference_provider, title: "A stored provider")
      active = create(:llm_connection).inference_provider
      active.update!(title: "Z active provider")

      get llm_connection_path

      rows = page.all("[data-test-selector^='llm-inference-provider--row-']")
      expect(rows.pluck("data-test-selector"))
        .to eq(["llm-inference-provider--row-#{active.id}", "llm-inference-provider--row-#{stored.id}"])
      expect(row_for(active)).to have_css("[data-test-selector='llm-inference-provider--active-label']")
      expect(row_for(stored)).to have_no_css("[data-test-selector='llm-inference-provider--active-label']")
    end

    it "offers activating only a provider that is not active" do
      stored = create(:inference_provider)
      active = create(:llm_connection).inference_provider

      get llm_connection_path

      expect(response.body).to include(activation_dialog_inference_provider_path(stored))
      expect(response.body).not_to include(activation_dialog_inference_provider_path(active))
    end

    it "offers deleting only a provider that is not active" do
      stored = create(:inference_provider)
      active = create(:llm_connection).inference_provider

      get llm_connection_path

      expect(response.body).to include(deletion_dialog_inference_provider_path(stored))
      expect(response.body).not_to include(deletion_dialog_inference_provider_path(active))
      expect(response.body).to include("Activate another provider first")
    end

    it "offers removing a key only from a provider that has one" do
      with_key = create(:inference_provider, api_key: "sk-test")
      without_key = create(:inference_provider, api_key: nil)

      get llm_connection_path

      expect(response.body).to include(delete_api_key_dialog_inference_provider_path(with_key))
      expect(response.body).not_to include(delete_api_key_dialog_inference_provider_path(without_key))
    end

    # No restriction on providers while the environment configures the connection.
    context "when the connection comes from the environment" do
      let!(:connection) { create(:llm_connection, :provisioned_from_env, base_url:) }
      let!(:stored) { create(:inference_provider) }

      before { allow(Setting).to receive(:llm_connection).and_return({ "base_url" => base_url }) }

      it "offers the same actions" do
        get llm_connection_path

        expect(page).to have_css("[data-test-selector='llm-inference-provider--new-button']")
        expect(response.body).to include(edit_dialog_inference_provider_path(connection.inference_provider))
        expect(response.body).to include(activation_dialog_inference_provider_path(stored))
        expect(response.body).to include(deletion_dialog_inference_provider_path(stored))
      end
    end
  end

  describe "GET new_dialog" do
    it "renders the form with everything a server needs" do
      get new_dialog_inference_providers_path, headers: turbo_headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("New inference provider", "inference_provider[title]",
                                       "inference_provider[api_format]", "inference_provider[base_url]",
                                       "inference_provider[api_key]")
    end

    it "offers only the formats a request can be sent in" do
      get new_dialog_inference_providers_path, headers: turbo_headers

      expect(response.body).to include("value=\"openai\"")
      expect(response.body).not_to include("value=\"bedrock\"")
    end

    it "does not warn when nothing is active yet" do
      get new_dialog_inference_providers_path, headers: turbo_headers

      expect(response.body).not_to include(I18n.t("admin.inference_providers.form.replaces_active"))
    end

    it "warns when saving replaces the active provider" do
      create(:llm_connection)

      get new_dialog_inference_providers_path, headers: turbo_headers

      expect(response.body).to include(CGI.escapeHTML(I18n.t("admin.inference_providers.form.replaces_active")))
    end
  end

  describe "POST /admin/inference_providers" do
    context "with a reachable server" do
      let!(:models_request) { mock_llm_models_response(elsewhere) }

      it "stores the provider" do
        post inference_providers_path, params: { inference_provider: new_provider_params }

        expect(response).to redirect_to(llm_connection_path)
        expect(InferenceProvider.last)
          .to have_attributes(title: "Elsewhere", base_url: elsewhere, api_key: "sk-test", api_format: "openai")
      end

      it "activates the first provider and fills the catalogue" do
        post inference_providers_path, params: { inference_provider: new_provider_params }

        expect(LlmConnection.active_connection.inference_provider).to eq(InferenceProvider.last)
        expect(LlmConnection.active_connection.available_model_ids).to contain_exactly("qwen3.6-27b", "bge-m3")
        expect(flash[:notice]).to eq(I18n.t(:notice_successful_create))
      end

      it "activates a later provider in place of the active one, which stays stored" do
        connection = create(:llm_connection, base_url:, api_key: "sk-original")
        previous = connection.inference_provider

        post inference_providers_path, params: { inference_provider: new_provider_params }

        expect(connection.reload.base_url).to eq(elsewhere)
        expect(previous.reload).to have_attributes(base_url:, api_key: "sk-original")
      end

      it "defaults a blank title to the host and port" do
        post inference_providers_path, params: { inference_provider: new_provider_params.merge(title: "") }

        expect(InferenceProvider.last.title).to eq("elsewhere.example")
      end

      it "stores no key when the field is left blank" do
        post inference_providers_path, params: { inference_provider: new_provider_params.merge(api_key: "") }

        expect(InferenceProvider.last.api_key).to be_nil
      end

      it "ignores custom headers, which no form offers" do
        post inference_providers_path,
             params: { inference_provider: new_provider_params.merge(custom_headers: { "X-Other" => "value" }) }

        expect(InferenceProvider.last.custom_headers).to eq({})
      end

      it "works while the connection comes from the environment, and lets go of its marks" do
        connection = create(:llm_connection, :provisioned_from_env, base_url:)
        allow(Setting).to receive(:llm_connection).and_return({ "base_url" => base_url })

        post inference_providers_path, params: { inference_provider: new_provider_params }

        expect(connection.reload).to have_attributes(base_url: elsewhere, env_provisioned_at: nil)
      end
    end

    # The case that matters for OpenProject's own gateway: chat completions are
    # routed, the model list is not.
    context "with a server that exposes no model list" do
      before { mock_llm_models_response(elsewhere, response_code: 405) }

      it "still stores and activates it and says that no models came back" do
        post inference_providers_path, params: { inference_provider: new_provider_params }

        expect(response).to redirect_to(llm_connection_path)
        expect(LlmConnection.active_connection.base_url).to eq(elsewhere)
        expect(flash[:warning]).to eq(I18n.t("admin.inference_providers.activate.no_models", title: "Elsewhere"))
      end
    end

    context "with an unreachable server" do
      before { mock_llm_models_response(elsewhere, timeout: true) }

      it "stores nothing and leaves the active provider alone" do
        connection = create(:llm_connection, base_url:)

        expect { post inference_providers_path, params: { inference_provider: new_provider_params }, headers: turbo_headers }
          .not_to change(InferenceProvider, :count)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(connection.reload.base_url).to eq(base_url)
      end

      # filter_parameters keeps a submitted key out of the logs and does nothing
      # for a response body, which a proxy, an APM or a HAR capture also sees.
      it "keeps the typed API key out of the response and says it must be retyped" do
        post inference_providers_path,
             params: { inference_provider: new_provider_params.merge(api_key: "sk-typed") },
             headers: turbo_headers

        expect(response.body).not_to include("sk-typed")
        expect(response.body).to include("was not saved and is not shown again")
        expect(response.body).not_to include("A key is stored")
      end
    end

    # Reachability and credentials still gate the save; only the model list is
    # treated as optional.
    context "with rejected credentials" do
      before { mock_llm_models_response(elsewhere, response_code: 401) }

      it "stores nothing and says why" do
        post inference_providers_path, params: { inference_provider: new_provider_params }, headers: turbo_headers

        expect(InferenceProvider.count).to eq(0)
        expect(response.body).to include("was rejected by the LLM server.")
      end
    end

    # The reported case: a host without its version segment answers 404 whatever
    # the key is, so accepting it saved a connection whose key had been judged by
    # nothing at all.
    context "with a URL that has no model list behind it" do
      before { mock_llm_models_response(elsewhere, response_code: 404) }

      it "refuses the save and says the key could not be verified either" do
        post inference_providers_path, params: { inference_provider: new_provider_params }, headers: turbo_headers

        expect(InferenceProvider.count).to eq(0)
        expect(response.body).to include("API key could not be verified")
      end
    end
  end

  describe "GET edit_dialog" do
    let(:provider) { create(:inference_provider, title: "My gateway", base_url:, api_key: "sk-original") }

    it "renders the form without the stored key" do
      get edit_dialog_inference_provider_path(provider), headers: turbo_headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Edit &quot;My gateway&quot;", "API key stored", "A key is stored")
      expect(response.body).not_to include("sk-original")
    end

    it "does not offer changing the server" do
      get edit_dialog_inference_provider_path(provider), headers: turbo_headers

      expect(response.body).to include("To use another server, create a new provider.")
      fragment = Capybara.string(response.body[%r{<template>(.*)</template>}m, 1])
      expect(fragment).to have_field("inference_provider[base_url]", disabled: true, with: base_url)
      expect(fragment).to have_field("inference_provider[api_format]", disabled: true, with: "OpenAI")
    end

    it "leaves credentials in the URL out of the form" do
      provider.update!(base_url: "https://user:url-password@example.com/v1?token=url-token")

      get edit_dialog_inference_provider_path(provider), headers: turbo_headers

      expect(response.body).not_to include("url-password", "url-token")
    end
  end

  describe "PATCH /admin/inference_providers/:id" do
    let!(:connection) { create(:llm_connection, :with_models, base_url:, api_key: "sk-original") }
    let(:provider) { connection.inference_provider }
    let!(:models_request) { mock_llm_models_response(base_url) }

    before { connection.update!(connection_fingerprint: connection.settings_fingerprint) }

    it "renames the provider without contacting the server" do
      patch inference_provider_path(provider), params: { inference_provider: { title: "Renamed", api_key: "" } }

      expect(response).to redirect_to(llm_connection_path)
      expect(provider.reload).to have_attributes(title: "Renamed", api_key: "sk-original")
      expect(models_request).not_to have_been_made
    end

    it "defaults a blank title to the host and port" do
      patch inference_provider_path(provider), params: { inference_provider: { title: "" } }

      expect(provider.reload.title).to eq("example.com")
    end

    it "does not change the server" do
      patch inference_provider_path(provider),
            params: { inference_provider: { title: "Renamed", base_url: elsewhere, api_format: "openrouter",
                                            custom_headers: { "X-Other" => "value" } } }

      expect(provider.reload).to have_attributes(title: "Renamed", base_url:, api_format: "openai", custom_headers: {})
    end

    context "with a new API key" do
      it "stores it once the server accepts it" do
        patch inference_provider_path(provider), params: { inference_provider: { api_key: "sk-rotated" } }

        expect(response).to redirect_to(llm_connection_path)
        expect(provider.reload.api_key).to eq("sk-rotated")
      end

      it "refreshes the catalogue of the active provider, keeping its models and defaults" do
        chat_model = connection.models.find_by!(external_id: "qwen3.6-27b")
        embedding_model = connection.models.find_by!(external_id: "bge-m3")
        connection.update!(default_chat_model: chat_model, default_embedding_model: embedding_model)
        model_ids = connection.models.order(:id).pluck(:id)

        expect { patch inference_provider_path(provider), params: { inference_provider: { api_key: "sk-rotated" } } }
          .to change { connection.reload.last_synced_at }

        expect(connection.models.order(:id).pluck(:id)).to eq(model_ids)
        expect(connection.default_chat_model_id).to eq(chat_model.id)
        expect(connection.default_embedding_model_id).to eq(embedding_model.id)
      end

      it "does not touch the catalogue for a provider that is not active" do
        stored = create(:inference_provider, base_url:)

        expect { patch inference_provider_path(stored), params: { inference_provider: { api_key: "sk-rotated" } } }
          .not_to(change { connection.reload.last_synced_at })
      end

      it "works while the connection comes from the environment, and lets go of its marks" do
        connection.update_columns(env_provisioned_at: Time.current)
        allow(Setting).to receive(:llm_connection).and_return({ "base_url" => base_url })

        patch inference_provider_path(provider), params: { inference_provider: { api_key: "sk-rotated" } }

        expect(provider.reload.api_key).to eq("sk-rotated")
        expect(connection.reload.env_provisioned_at).to be_nil
      end
    end

    context "with a key the server rejects" do
      let!(:models_request) { mock_llm_models_response(base_url, response_code: 401) }

      it "keeps the stored key and does not echo the typed one" do
        patch inference_provider_path(provider),
              params: { inference_provider: { api_key: "sk-rejected" } },
              headers: turbo_headers

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("was rejected by the LLM server.")
        expect(response.body).not_to include("sk-rejected", "sk-original")
        expect(provider.reload.api_key).to eq("sk-original")
      end
    end
  end

  describe "activating" do
    let!(:connection) { create(:llm_connection, :with_models, base_url:, api_key: "sk-original") }
    let!(:provider) { create(:inference_provider, title: "Elsewhere", base_url: elsewhere, api_key: "sk-elsewhere") }

    before do
      connection.update!(connection_fingerprint: connection.settings_fingerprint,
                         default_chat_model: connection.models.find_by!(external_id: "qwen3.6-27b"))
    end

    it "renders the confirmation, naming both providers and what is lost" do
      connection.inference_provider.update!(title: "Current")

      get activation_dialog_inference_provider_path(provider), headers: turbo_headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Activate &quot;Elsewhere&quot;?", "Current", "Elsewhere",
                                       "default models and the model of each feature")
    end

    it "escapes the titles in the confirmation" do
      connection.inference_provider.update!(title: "<script>current</script>")
      provider.update!(title: "<script>next</script>")

      get activation_dialog_inference_provider_path(provider), headers: turbo_headers

      expect(response.body).not_to include("<script>current", "<script>next")
    end

    context "with a reachable server" do
      before { mock_llm_models_response(elsewhere, models: [{ id: "llama4-8b", object: "model", owned_by: "vllm" }]) }

      it "switches and replaces the catalogue" do
        post activate_inference_provider_path(provider)

        expect(response).to redirect_to(llm_connection_path)
        expect(flash[:notice]).to eq(I18n.t("admin.inference_providers.activate.success", title: "Elsewhere"))
        connection.reload
        expect(connection.api_key).to eq("sk-elsewhere")
        expect(connection.available_model_ids).to contain_exactly("llama4-8b")
        expect(connection.default_chat_model_id).to be_nil
      end

      it "keeps the features switch as it is" do
        Setting.llm_features_enabled = true

        post activate_inference_provider_path(provider)

        expect(Setting.llm_features_enabled?).to be(true)
      end

      it "works while the connection comes from the environment, and lets go of its marks" do
        connection.update_columns(env_provisioned_at: Time.current)
        allow(Setting).to receive(:llm_connection).and_return({ "base_url" => base_url })

        post activate_inference_provider_path(provider)

        expect(connection.reload).to have_attributes(base_url: elsewhere, env_provisioned_at: nil)

        get llm_connection_path

        expect(response.body).to include("the active provider does not come from them")
      end

      it "needs nothing entered again when switching back" do
        mock_llm_models_response(base_url)
        previous = connection.inference_provider

        post activate_inference_provider_path(provider)
        post activate_inference_provider_path(previous)

        expect(connection.reload).to have_attributes(base_url:, api_key: "sk-original")
        expect(connection.available_model_ids).to contain_exactly("qwen3.6-27b", "bge-m3")
      end

      describe "the health report on the page" do
        let!(:report) { store_health_report(connection) }
        let(:health_summary) { "[data-test-selector='llm-connection--health-summary']" }

        it "belongs to the previous provider once another one is active" do
          post activate_inference_provider_path(provider)

          get llm_connection_path

          expect(page).to have_no_css(health_summary)
          expect(page).to have_text("This provider has not been checked yet.")
        end

        it "is shown again when switching back" do
          mock_llm_models_response(base_url)
          previous = connection.inference_provider

          post activate_inference_provider_path(provider)
          post activate_inference_provider_path(previous)

          get llm_connection_path

          expect(page).to have_css(health_summary)
          expect(connection.reload.latest_health_report).to eq(report)
        end

        it "takes the provider's own report over another provider's newer one" do
          own = store_health_report(provider, created_at: 1.year.ago)

          post activate_inference_provider_path(provider)

          expect(connection.reload.latest_health_report).to eq(own)
        end
      end
    end

    context "with an unreachable server" do
      before { mock_llm_models_response(elsewhere, timeout: true) }

      it "switches anyway and warns" do
        post activate_inference_provider_path(provider)

        expect(response).to redirect_to(llm_connection_path)
        expect(connection.reload.base_url).to eq(elsewhere)
        expect(flash[:warning]).to eq(I18n.t("admin.inference_providers.activate.no_models", title: "Elsewhere"))
      end

      it "warns even when models entered by hand remain" do
        create(:llm_model, :manual, llm_connection: connection, external_id: "hand-typed")

        post activate_inference_provider_path(provider)

        expect(connection.reload.available_model_ids).to contain_exactly("hand-typed")
        expect(flash[:warning]).to be_present
      end
    end
  end

  describe "removing the API key" do
    let!(:connection) { create(:llm_connection, base_url:, api_key: "sk-original") }
    let(:provider) { connection.inference_provider }

    it "renders the confirmation" do
      get delete_api_key_dialog_inference_provider_path(provider), headers: turbo_headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Remove the stored API key?")
    end

    it "removes the key but keeps the provider" do
      delete api_key_inference_provider_path(provider)

      expect(response).to redirect_to(llm_connection_path)
      expect(flash[:notice]).to eq(I18n.t("admin.inference_providers.delete_api_key.success"))
      expect(provider.reload).to have_attributes(api_key: nil, base_url:)
      expect(connection.reload.inference_provider).to eq(provider)
    end

    it "removes the key of a provider that is not active, leaving the active one alone" do
      stored = create(:inference_provider, api_key: "sk-stored")

      delete api_key_inference_provider_path(stored)

      expect(stored.reload.api_key).to be_nil
      expect(connection.reload.api_key).to eq("sk-original")
    end

    it "does not offer removing it again" do
      delete api_key_inference_provider_path(provider)
      get llm_connection_path

      expect(response.body).not_to include(delete_api_key_dialog_inference_provider_path(provider))
      expect(row_for(provider)).to have_text("None")
    end

    it "works while the connection comes from the environment, and lets go of its marks" do
      connection.update_columns(env_provisioned_at: Time.current)
      allow(Setting).to receive(:llm_connection).and_return({ "base_url" => base_url })

      delete api_key_inference_provider_path(provider)

      expect(provider.reload.api_key).to be_nil
      expect(connection.reload.env_provisioned_at).to be_nil
    end

    it "removes the key from a provider that no longer passes validation" do
      provider.update_column(:base_url, "not a url")

      delete api_key_inference_provider_path(provider)

      expect(response).to redirect_to(llm_connection_path)
      expect(provider.reload.api_key).to be_nil
    end

    it "does not contact the server" do
      delete api_key_inference_provider_path(provider)

      expect(a_request(:any, /example\.com/)).not_to have_been_made
    end
  end

  describe "deleting" do
    let!(:connection) { create(:llm_connection) }
    let!(:stored) { create(:inference_provider, title: "Stored") }

    it "renders the confirmation" do
      get deletion_dialog_inference_provider_path(stored), headers: turbo_headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Delete Stored?")
    end

    it "deletes a provider that is not active" do
      delete inference_provider_path(stored)

      expect(response).to redirect_to(llm_connection_path)
      expect(flash[:notice]).to eq(I18n.t(:notice_successful_delete))
      expect(InferenceProvider.exists?(stored.id)).to be(false)
    end

    it "deletes the provider's health reports and no others" do
      deleted = store_health_report(stored)
      kept = store_health_report(connection)

      delete inference_provider_path(stored)

      expect(HealthReport.exists?(deleted.id)).to be(false)
      expect(HealthReport.exists?(kept.id)).to be(true)
    end

    it "refuses the active provider" do
      provider = connection.inference_provider

      delete inference_provider_path(provider)

      expect(response).to redirect_to(llm_connection_path)
      expect(flash[:error]).to include("The provider is active. Activate another provider first.")
      expect(InferenceProvider.exists?(provider.id)).to be(true)
    end

    context "with an embedding model stored for it" do
      before { create(:embedding_model, inference_provider: stored) }

      it "refuses and says what to do" do
        delete inference_provider_path(stored)

        expect(response).to redirect_to(llm_connection_path)
        expect(flash[:error]).to include("Embedding models are stored for this provider. Delete them first.")
        expect(InferenceProvider.exists?(stored.id)).to be(true)
      end

      it "locks the row's delete action and gives the reason" do
        get llm_connection_path

        expect(response.body).to include("Delete the embedding models stored for it first")
      end
    end

    it "works while the connection comes from the environment" do
      connection.update_columns(env_provisioned_at: Time.current)
      allow(Setting).to receive(:llm_connection).and_return({ "base_url" => "https://example.com/v1" })

      delete inference_provider_path(stored)

      expect(InferenceProvider.exists?(stored.id)).to be(false)
    end
  end
end
