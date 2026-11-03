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

RSpec.describe "Admin LLM connection", :llm_server_helpers, :skip_csrf, :webmock,
               type: :rails_request, with_flag: { llm_connection: true } do
  let(:admin) { create(:admin) }
  let(:non_admin) { create(:user) }
  let(:base_url) { "https://example.com/v1" }
  let(:features_switch) { "Enable LLMs for this instance" }
  let(:turbo_headers) { { "Accept" => "text/vnd.turbo-stream.html" } }

  describe "with the feature flag off", with_flag: { llm_connection: false } do
    before { login_as admin }

    it "does not expose the endpoints" do
      get llm_connection_path
      expect(response).to have_http_status(:not_found)

      patch llm_connection_path, params: { llm_connection: { llm_features_enabled: "1" } }
      expect(response).to have_http_status(:not_found)

      post setup_llm_connection_path, params: { llm_features_enabled: "1", inference_provider: { base_url: } }
      expect(response).to have_http_status(:not_found)
      expect(InferenceProvider.count).to eq(0)
    end
  end

  describe "GET /admin/llm_connection" do
    it "is not reachable for non-admins" do
      login_as non_admin
      get llm_connection_path

      expect(response).not_to have_http_status(:ok)
    end

    context "when logged in as admin" do
      before { login_as admin }

      context "without a provider" do
        it "offers the switch, with the server fields hidden until it is ticked" do
          get llm_connection_path

          expect(response).to have_http_status(:ok)
          expect(page).to have_field(features_switch, disabled: false, checked: false)
          expect(page).to have_field("inference_provider[base_url]", visible: :hidden)
          expect(page).to have_css("form[action='#{setup_llm_connection_path}']")
          expect(response.body).not_to include("llm-settings--tabs")
        end

        it "shows the server fields once the features are on, with no tabs to lead nowhere",
           with_settings: { llm_features_enabled: true } do
          get llm_connection_path

          expect(page).to have_field(features_switch, checked: true)
          expect(page).to have_field("inference_provider[base_url]")
          expect(response.body).not_to include("llm-settings--tabs")
        end

        it "points at no tab" do
          get llm_connection_path

          expect(response.body).to include("Connect OpenProject to an LLM server")
          expect(response.body).not_to include("review the models offered by the server")
        end
      end

      context "with a provider and the features switched off" do
        let!(:provider) { create(:inference_provider, base_url:, api_key: "sk-original") }

        it "only offers the switch" do
          get llm_connection_path

          expect(page).to have_field(features_switch, disabled: false)
          expect(page).to have_button("Save")
          expect(page).to have_css("form[action='#{llm_connection_path}']")
          expect(page).to have_no_field("inference_provider[base_url]", visible: :all)
          expect(response.body).not_to include("llm-settings--tabs")
        end

        it "does not render the settings of the provider" do
          get llm_connection_path

          expect(response.body).not_to include("sk-original")
        end
      end

      context "with a provider and the features switched on", with_settings: { llm_features_enabled: true } do
        before { create(:inference_provider, base_url:) }

        it "points at the Models tab" do
          get llm_connection_path

          expect(response.body).to include("review the models offered by the server")
          expect(page).to have_css("a[href='#{llm_models_path}']", text: "Models")
        end

        it "offers the Models and Feature configuration tabs" do
          get llm_connection_path

          expect(response.body).to include("llm-settings--tabs")
          expect(response.body).to include(llm_models_path)
          expect(response.body).to include(llm_feature_bindings_path)
        end
      end

      it "locks the features switch while the environment sets it" do
        allow(Settings::Definition[:llm_features_enabled]).to receive_messages(writable?: false, value: true)
        create(:inference_provider, base_url:)

        get llm_connection_path

        expect(page).to have_field(features_switch, disabled: true)
        expect(page).to have_no_button("Save")
        expect(response.body).to include("stays locked while the environment sets it")
      end

      context "when the environment wrote the connection" do
        before do
          create(:inference_provider, base_url:)
          create(:llm_connection, :provisioned_from_env)
          allow(Setting).to receive_messages(llm_connection: { "base_url" => base_url },
                                             llm_features_enabled?: true)
        end

        it "leaves the features switch usable" do
          get llm_connection_path

          expect(page).to have_field(features_switch, disabled: false)
          expect(page).to have_button("Save")
        end

        it "says when the environment applied the values and what the next seed does" do
          get llm_connection_path

          expect(response.body).to include("The environment variables were applied on")
          expect(response.body).to include("The next database seed applies them again")
        end

        it "warns once the variables differ from the ones that were applied" do
          LlmConnection.current
                       .update_columns(env_fingerprint: LlmConnection.env_fingerprint("base_url" => "https://old.example/v1"))

          get llm_connection_path

          expect(response.body).to include("have changed since they were applied")
        end

        it "does not warn while the applied variables are still the current ones" do
          LlmConnection.current
                       .update_columns(env_fingerprint: LlmConnection.env_fingerprint("base_url" => base_url))

          get llm_connection_path

          expect(response.body).not_to include("have changed since they were applied")
        end
      end

      context "when the environment configures a provider that was never seeded" do
        before { allow(Setting).to receive(:llm_connection).and_return({ "base_url" => base_url }) }

        it "says that the next seed applies the variables" do
          get llm_connection_path

          expect(response.body).to include("have not been applied yet")
        end
      end

      context "when the environment no longer configures a connection it wrote" do
        before do
          create(:inference_provider, base_url:)
          create(:llm_connection, :provisioned_from_env)
        end

        it "says nothing about the environment" do
          get llm_connection_path

          expect(response.body).not_to include("environment variables")
        end
      end
    end
  end

  describe "POST /admin/llm_connection/setup" do
    let(:provider_params) { { title: "", api_format: "openai", base_url:, api_key: "sk-typed" } }

    before do
      login_as admin
      Setting.llm_features_enabled = false
    end

    context "when the server answers" do
      let!(:models_request) { mock_llm_models_response(base_url) }

      it "creates the provider and switches the features on" do
        post setup_llm_connection_path, params: { llm_features_enabled: "1", inference_provider: provider_params }

        expect(response).to redirect_to(llm_connection_path)
        expect(InferenceProvider.sole).to have_attributes(title: "example.com", base_url:, api_key: "sk-typed")
        expect(Setting.llm_features_enabled?).to be(true)
        expect(flash[:notice]).to eq(I18n.t("admin.llm_connections.update.success"))
      end

      it "checks the server first" do
        post setup_llm_connection_path, params: { llm_features_enabled: "1", inference_provider: provider_params }

        expect(models_request).to have_been_made
      end

      it "fetches the model list in the background" do
        expect do
          post setup_llm_connection_path, params: { llm_features_enabled: "1", inference_provider: provider_params }
        end.to have_enqueued_job(Llm::SyncModelsJob).once
      end

      it "stores no key for a blank one" do
        post setup_llm_connection_path,
             params: { llm_features_enabled: "1", inference_provider: provider_params.merge(api_key: "") }

        expect(InferenceProvider.sole.api_key).to be_nil
      end

      it "schedules the health check" do
        post setup_llm_connection_path, params: { llm_features_enabled: "1", inference_provider: provider_params }

        expect(GoodJob::Setting.cron_key_enabled?(Llm::HealthCheckJob::CRON_JOB_KEY)).to be(true)
      end

      it "takes the switch from the environment when it is fixed there" do
        allow(Settings::Definition[:llm_features_enabled]).to receive_messages(writable?: false, value: true)

        post setup_llm_connection_path, params: { inference_provider: provider_params }

        expect(InferenceProvider.count).to eq(1)
        expect(flash[:error]).to be_blank
      end
    end

    context "when the server refuses" do
      before { mock_llm_models_response(base_url, response_code: 401) }

      it "saves neither" do
        post setup_llm_connection_path, params: { llm_features_enabled: "1", inference_provider: provider_params },
                                        headers: turbo_headers

        expect(InferenceProvider.count).to eq(0)
        expect(Setting.llm_features_enabled?).to be(false)
      end

      it "shows the error on the form, keeps the box ticked and does not echo the key" do
        post setup_llm_connection_path, params: { llm_features_enabled: "1", inference_provider: provider_params },
                                        headers: turbo_headers

        expect(response.body).to include("was rejected by the LLM server")
        expect(Nokogiri::HTML(response.parsed_body).at_css("input[type='checkbox'][name='llm_features_enabled']")["checked"])
          .to be_present
        expect(response.body).not_to include("sk-typed")
      end
    end

    it "only saves the switch when the box is not ticked" do
      Setting.llm_features_enabled = true

      post setup_llm_connection_path, params: { llm_features_enabled: "0", inference_provider: provider_params }

      expect(response).to redirect_to(llm_connection_path)
      expect(InferenceProvider.count).to eq(0)
      expect(Setting.llm_features_enabled?).to be(false)
    end

    it "is refused for a non-admin" do
      login_as non_admin

      post setup_llm_connection_path, params: { llm_features_enabled: "1", inference_provider: provider_params }

      expect(response).to have_http_status(:forbidden)
      expect(InferenceProvider.count).to eq(0)
    end
  end

  describe "PATCH /admin/llm_connection" do
    let!(:provider) { create(:inference_provider, base_url:, api_key: "sk-test") }

    before { login_as admin }

    context "when the administrator switches LLMs on" do
      before { Setting.llm_features_enabled = false }

      let!(:models_request) { mock_llm_models_response(base_url) }

      it "switches them on without contacting the server" do
        patch llm_connection_path, params: { llm_connection: { llm_features_enabled: "1" } }

        expect(response).to have_http_status(:see_other)
        expect(Setting.llm_features_enabled?).to be(true)
        expect(flash[:notice]).to eq(I18n.t("admin.llm_connections.update.success"))
        expect(models_request).not_to have_been_made
      end
    end

    context "when the administrator switches LLMs off" do
      # Not with_settings:, which stubs Setting.[] and would hide the write.
      before { Setting.llm_features_enabled = true }

      it "confirms that the features are off" do
        patch llm_connection_path, params: { llm_connection: { llm_features_enabled: "0" } }

        expect(Setting.llm_features_enabled?).to be(false)
        expect(flash[:notice]).to eq(I18n.t("admin.llm_connections.update.disabled"))
      end

      it "keeps the provider and its key" do
        patch llm_connection_path, params: { llm_connection: { llm_features_enabled: "0" } }

        expect(provider.reload).to have_attributes(base_url:, api_key: "sk-test")
      end
    end

    context "when the features switch is set through the environment" do
      before do
        allow(Settings::Definition[:llm_features_enabled]).to receive_messages(writable?: false, value: true)
      end

      it "leaves the switch to the environment" do
        patch llm_connection_path, params: { llm_connection: { llm_features_enabled: "0" } }

        expect(response).to have_http_status(:see_other)
        expect(Setting.llm_features_enabled?).to be(true)
      end

      it "still schedules the health check" do
        allow(Llm::HealthCheckJob).to receive(:toggle_cron_job)

        patch llm_connection_path, params: { llm_connection: { llm_features_enabled: "0" } }

        expect(Llm::HealthCheckJob).to have_received(:toggle_cron_job)
      end
    end

    context "when the environment wrote the connection" do
      before do
        create(:llm_connection, :provisioned_from_env)
        Setting.llm_features_enabled = true
        allow(Setting).to receive(:llm_connection).and_return({ "base_url" => base_url })
      end

      it "saves the switch and leaves the markers alone" do
        patch llm_connection_path, params: { llm_connection: { llm_features_enabled: "0" } }

        expect(Setting.llm_features_enabled?).to be(false)
        expect(flash[:notice]).to eq(I18n.t("admin.llm_connections.update.disabled"))
        expect(LlmConnection.current).to be_configured_from_env
      end
    end

    it "leaves the server settings alone" do
      patch llm_connection_path,
            params: { llm_connection: { llm_features_enabled: "1", base_url: "https://elsewhere.example/v1",
                                        api_key: "sk-crafted" } }

      expect(provider.reload).to have_attributes(base_url:, api_key: "sk-test")
    end
  end

  describe "the default models" do
    let!(:provider) { create(:inference_provider, :with_models, base_url: "https://example.com/v1") }
    let(:connection) { LlmConnection.current }

    before { login_as admin }

    it "are chosen on the Models tab, not here" do
      patch llm_connection_path, params: { llm_connection: { default_chat_model_id: provider.models.first.id } }

      expect(connection.reload.default_chat_model_id).to be_nil
    end
  end
end
