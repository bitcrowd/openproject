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
  let(:new_provider_params) { { title: "Elsewhere", api_format: "openai", base_url: elsewhere, api_key: "sk-typed" } }

  def row_for(provider)
    page.find("[data-test-selector='llm-inference-provider--row-#{provider.id}']")
  end

  def store_health_report(owner)
    group = HealthReport::ResultGroup.new(key: :configuration, results: [HealthReport::Result.success(:enabled)])
    owner.health_reports.create!(results: [group])
  end

  def dialog_html = CGI.unescapeHTML(response.body)

  before do
    login_as admin
    Setting.llm_features_enabled = true
  end

  describe "with the features switched off" do
    let!(:provider) { create(:inference_provider, base_url:) }

    before { Setting.llm_features_enabled = false }

    it "sends every endpoint back to the switch" do
      [
        -> { get new_dialog_inference_providers_path, headers: turbo_headers },
        -> { post inference_providers_path, params: { inference_provider: new_provider_params } },
        -> { get edit_dialog_inference_provider_path(provider), headers: turbo_headers },
        -> { patch inference_provider_path(provider), params: { inference_provider: { title: "Changed" } } },
        -> { get deletion_dialog_inference_provider_path(provider), headers: turbo_headers },
        -> { delete inference_provider_path(provider) },
        -> { get delete_api_key_dialog_inference_provider_path(provider), headers: turbo_headers },
        -> { delete api_key_inference_provider_path(provider) }
      ].each do |request|
        request.call

        expect(response).to redirect_to(llm_connection_path)
      end

      expect(provider.reload).to have_attributes(title: provider.title, api_key: "sk-test-key")
    end
  end

  describe "with the feature flag off", with_flag: { llm_connection: false } do
    let!(:provider) { create(:inference_provider, base_url:) }

    it "does not expose the endpoints" do
      get new_dialog_inference_providers_path, headers: turbo_headers
      expect(response).to have_http_status(:not_found)

      post inference_providers_path, params: { inference_provider: new_provider_params }
      expect(response).to have_http_status(:not_found)

      delete inference_provider_path(provider)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "as a non-admin" do
    let!(:provider) { create(:inference_provider, base_url:) }

    before { login_as create(:user) }

    it "refuses every endpoint" do
      post inference_providers_path, params: { inference_provider: new_provider_params }
      expect(response).to have_http_status(:forbidden)

      patch inference_provider_path(provider), params: { inference_provider: { title: "Changed" } }
      expect(response).to have_http_status(:forbidden)

      delete inference_provider_path(provider)
      expect(response).to have_http_status(:forbidden)

      delete api_key_inference_provider_path(provider)
      expect(response).to have_http_status(:forbidden)

      expect(provider.reload.api_key).to eq("sk-test-key")
    end
  end

  describe "the list on the settings page" do
    let!(:provider) { create(:inference_provider, title: "Local Ollama", base_url:, api_format: "openrouter") }

    it "shows the settings of a provider" do
      get llm_connection_path

      expect(row_for(provider)).to have_text("Local Ollama")
      expect(row_for(provider)).to have_text(base_url)
      expect(row_for(provider)).to have_text("OpenRouter")
      expect(row_for(provider)).to have_text("Stored")
    end

    it "says when a provider has no key" do
      provider.update!(api_key: nil)

      get llm_connection_path

      expect(row_for(provider)).to have_text("None")
    end

    it "does not show the key or anything else that can carry a credential" do
      provider.update_columns(base_url: "https://user:url-password@example.com/v1?api-key=query-secret")

      get llm_connection_path

      expect(response.body).not_to include("sk-test-key", "url-password", "query-secret")
    end

    it "lists every provider, by title" do
      create(:inference_provider, title: "A first")

      get llm_connection_path

      expect(page.all("[data-test-selector^='llm-inference-provider--row-']").map(&:text).first).to include("A first")
    end

    it "offers removing a key only from a provider that has one" do
      keyless = create(:inference_provider, api_key: nil)

      get llm_connection_path

      expect(page).to have_css("[data-test-selector='llm-inference-provider--delete-api-key-#{provider.id}']", visible: :all)
      expect(page).to have_no_css("[data-test-selector='llm-inference-provider--delete-api-key-#{keyless.id}']", visible: :all)
    end

    it "is gone while the features are switched off" do
      Setting.llm_features_enabled = false

      get llm_connection_path

      expect(page).to have_no_test_selector("llm-inference-provider--box")
    end
  end

  describe "GET new_dialog" do
    it "renders the form with everything a server needs" do
      get new_dialog_inference_providers_path, headers: turbo_headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("inference_provider[title]", "inference_provider[api_format]",
                                       "inference_provider[base_url]", "inference_provider[api_key]")
    end
  end

  describe "POST /admin/inference_providers" do
    context "with a reachable server" do
      before { mock_llm_models_response(elsewhere) }

      it "stores the provider" do
        post inference_providers_path, params: { inference_provider: new_provider_params }

        expect(response).to redirect_to(llm_connection_path)
        expect(InferenceProvider.sole)
          .to have_attributes(title: "Elsewhere", base_url: elsewhere, api_key: "sk-typed", api_format: "openai")
      end

      it "fetches its model list in the background" do
        expect { post inference_providers_path, params: { inference_provider: new_provider_params } }
          .to have_enqueued_job(Llm::SyncModelsJob).once
      end

      it "leaves other providers alone" do
        other = create(:inference_provider, :with_models, base_url:)

        post inference_providers_path, params: { inference_provider: new_provider_params }

        expect(other.reload.models.count).to eq(2)
      end

      it "defaults a blank title to the host and port" do
        post inference_providers_path, params: { inference_provider: new_provider_params.merge(title: "") }

        expect(InferenceProvider.sole.title).to eq("elsewhere.example")
      end

      it "stores no key when the field is left blank" do
        post inference_providers_path, params: { inference_provider: new_provider_params.merge(api_key: "") }

        expect(InferenceProvider.sole.api_key).to be_nil
      end

      it "ignores custom headers, which no form offers" do
        post inference_providers_path,
             params: { inference_provider: new_provider_params.merge(custom_headers: { "X-Crafted" => "1" }) }

        expect(InferenceProvider.sole.custom_headers).to eq({})
      end

      it "refuses a title another provider has" do
        create(:inference_provider, title: "Elsewhere")

        post inference_providers_path, params: { inference_provider: new_provider_params }, headers: turbo_headers

        expect(response).to have_http_status(:unprocessable_entity)
        expect(InferenceProvider.where(base_url: elsewhere)).to be_empty
      end
    end

    context "with an unreachable server" do
      before { mock_llm_models_response(elsewhere, timeout: true) }

      it "stores nothing" do
        post inference_providers_path, params: { inference_provider: new_provider_params }, headers: turbo_headers

        expect(response).to have_http_status(:unprocessable_entity)
        expect(InferenceProvider.count).to eq(0)
      end

      it "keeps the typed API key out of the response and says it must be retyped" do
        post inference_providers_path, params: { inference_provider: new_provider_params }, headers: turbo_headers

        expect(response.body).not_to include("sk-typed")
        expect(dialog_html).to include(I18n.t("admin.inference_providers.form.api_key_caption_discarded"))
      end
    end

    context "with rejected credentials" do
      before { mock_llm_models_response(elsewhere, response_code: 401) }

      it "stores nothing and says why" do
        post inference_providers_path, params: { inference_provider: new_provider_params }, headers: turbo_headers

        expect(InferenceProvider.count).to eq(0)
        expect(response.body).to include("was rejected by the LLM server")
      end
    end

    context "with a URL that has no model list behind it" do
      before { mock_llm_models_response(elsewhere, response_code: 404) }

      it "refuses the save and says the key could not be verified either" do
        post inference_providers_path, params: { inference_provider: new_provider_params }, headers: turbo_headers

        expect(InferenceProvider.count).to eq(0)
        expect(response.body).to include("has no model list at this address")
      end
    end
  end

  describe "GET edit_dialog" do
    let!(:provider) { create(:inference_provider, base_url:, api_key: "sk-stored-key") }

    it "renders the form without the stored key" do
      get edit_dialog_inference_provider_path(provider), headers: turbo_headers

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("sk-stored-key")
      expect(dialog_html).to include(I18n.t("admin.inference_providers.form.api_key_placeholder_stored"))
    end

    it "offers changing the format but not the server" do
      get edit_dialog_inference_provider_path(provider), headers: turbo_headers

      html = Nokogiri::HTML(response.parsed_body)
      expect(html.at_css("input[name='inference_provider[base_url]']")["disabled"]).to be_present
      expect(html.at_css("select[name='inference_provider[api_format]']")["disabled"]).to be_nil
    end

    it "leaves credentials in the URL out of the form" do
      provider.update_columns(base_url: "https://user:url-password@example.com/v1?api-key=query-secret")

      get edit_dialog_inference_provider_path(provider), headers: turbo_headers

      expect(response.body).not_to include("url-password", "query-secret")
    end
  end

  describe "PATCH /admin/inference_providers/:id" do
    let!(:provider) { create(:inference_provider, :with_models, title: "Old", base_url:, api_key: "sk-stored-key") }
    let!(:models_request) { mock_llm_models_response(base_url) }

    it "renames the provider without contacting the server" do
      patch inference_provider_path(provider), params: { inference_provider: { title: "New" } }

      expect(response).to redirect_to(llm_connection_path)
      expect(provider.reload.title).to eq("New")
      expect(models_request).not_to have_been_made
    end

    it "defaults a blank title to the host and port" do
      patch inference_provider_path(provider), params: { inference_provider: { title: "" } }

      expect(provider.reload.title).to eq("example.com")
    end

    it "does not change the server" do
      patch inference_provider_path(provider), params: { inference_provider: { title: "New", base_url: elsewhere } }

      expect(provider.reload.base_url).to eq(base_url)
    end

    it "keeps the stored key when the field is left blank" do
      patch inference_provider_path(provider), params: { inference_provider: { title: "New", api_key: "" } }

      expect(provider.reload.api_key).to eq("sk-stored-key")
      expect(models_request).not_to have_been_made
    end

    context "with a new API key" do
      it "stores it once the server accepts it" do
        patch inference_provider_path(provider), params: { inference_provider: { api_key: "sk-rotated" } }

        expect(provider.reload.api_key).to eq("sk-rotated")
        expect(models_request).to have_been_made
      end

      it "leaves refreshing the list to the administrator" do
        expect { patch inference_provider_path(provider), params: { inference_provider: { api_key: "sk-rotated" } } }
          .not_to have_enqueued_job(Llm::SyncModelsJob)

        expect(provider.reload.last_synced_at).to be_within(1.minute).of(provider.last_synced_at)
      end
    end

    context "with a key the server rejects" do
      before { mock_llm_models_response(base_url, response_code: 401) }

      it "keeps the stored key and does not echo the typed one" do
        patch inference_provider_path(provider), params: { inference_provider: { api_key: "sk-wrong" } },
                                                 headers: turbo_headers

        expect(response).to have_http_status(:unprocessable_entity)
        expect(provider.reload.api_key).to eq("sk-stored-key")
        expect(response.body).not_to include("sk-wrong")
      end
    end

    context "with another API format" do
      it "stores it once the server answers, and leaves the list as it is" do
        patch inference_provider_path(provider), params: { inference_provider: { api_format: "openrouter" } }

        expect(provider.reload.api_format).to eq("openrouter")
        expect(models_request).to have_been_made
        expect(provider.models.count).to eq(2)
      end

      it "keeps the stored format when the server does not answer" do
        mock_llm_models_response(base_url, timeout: true)

        patch inference_provider_path(provider), params: { inference_provider: { api_format: "openrouter" } },
                                                 headers: turbo_headers

        expect(response).to have_http_status(:unprocessable_entity)
        expect(provider.reload.api_format).to eq("openai")
      end
    end
  end

  describe "removing the API key" do
    let!(:provider) { create(:inference_provider, base_url:) }

    it "renders the confirmation" do
      get delete_api_key_dialog_inference_provider_path(provider), headers: turbo_headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("admin.inference_providers.delete_api_key.heading"))
    end

    it "removes the key but keeps the provider" do
      delete api_key_inference_provider_path(provider)

      expect(response).to redirect_to(llm_connection_path)
      expect(flash[:notice]).to eq(I18n.t("admin.inference_providers.delete_api_key.success"))
      expect(provider.reload).to have_attributes(api_key: nil, base_url:)
    end

    it "does not contact the server" do
      delete api_key_inference_provider_path(provider)

      expect(a_request(:any, /example\.com/)).not_to have_been_made
    end
  end

  describe "deleting" do
    let!(:provider) { create(:inference_provider, :with_models, title: "Gateway", base_url:) }
    let(:chat_model) { provider.models.find_by!(external_id: "qwen3.6-27b") }
    let(:connection) { LlmConnection.current }

    it "renders the confirmation when nothing uses it" do
      get deletion_dialog_inference_provider_path(provider), headers: turbo_headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("admin.inference_providers.destroy.description"))
      expect(response.body).to include(%(action="#{inference_provider_path(provider)}"))
    end

    it "deletes it with its list, verdicts and health reports" do
      create(:llm_capability_verdict, inference_provider: provider, model_id: "bge-m3")
      store_health_report(provider)
      other = create(:inference_provider)
      store_health_report(other)

      delete inference_provider_path(provider)

      expect(response).to redirect_to(llm_connection_path)
      expect(InferenceProvider.exists?(provider.id)).to be(false)
      expect(LlmModel.where(external_id: "bge-m3")).to be_empty
      expect(LlmCapabilityVerdict.count).to eq(0)
      expect(HealthReport.where(subject_type: "InferenceProvider").pluck(:subject_id)).to eq([other.id])
    end

    it "returns to the form once the last one is gone" do
      delete inference_provider_path(provider)
      get llm_connection_path

      expect(page).to have_css("form[action='#{setup_llm_connection_path}']")
      expect(response.body).not_to include("llm-settings--tabs")
    end

    it "stops the scheduled health check once the last one is gone" do
      Llm::HealthCheckJob.toggle_cron_job

      delete inference_provider_path(provider)

      expect(GoodJob::Setting.cron_key_enabled?(Llm::HealthCheckJob::CRON_JOB_KEY)).to be(false)
    end

    shared_examples "a provider in use" do |named:|
      it "names what uses it instead of offering the deletion" do
        get deletion_dialog_inference_provider_path(provider), headers: turbo_headers

        expect(dialog_html).to include("can't be deleted while its models are in use", named, "qwen3.6-27b")
        expect(response.body).not_to include(%(action="#{inference_provider_path(provider)}"))
      end

      it "refuses the deletion" do
        delete inference_provider_path(provider)

        expect(response).to redirect_to(llm_connection_path)
        expect(flash[:error].to_s).to include(named, "qwen3.6-27b")
        expect(InferenceProvider.exists?(provider.id)).to be(true)
        expect(provider.models.count).to eq(2)
      end
    end

    context "when a semantic index uses one of its models" do
      before { create(:semantic_index, title: "Docs", llm_model: chat_model) }

      it_behaves_like "a provider in use", named: "Docs"
    end

    context "when a feature is bound to one of its models" do
      before { create(:llm_feature_binding, llm_model: chat_model) }

      it_behaves_like "a provider in use", named: "Description assistant"
    end

    context "when one of its models is a default" do
      before { connection.update!(default_chat_model: chat_model) }

      it_behaves_like "a provider in use", named: "Default chat model"
    end
  end
end
