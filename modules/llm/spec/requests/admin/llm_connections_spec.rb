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
  let(:new_provider_button) { "[data-test-selector='llm-inference-provider--new-button']" }

  describe "with the feature flag off", with_flag: { llm_connection: false } do
    before { login_as admin }

    it "does not expose the endpoints" do
      get llm_connection_path
      expect(response).to have_http_status(:not_found)

      patch llm_connection_path, params: { llm_connection: { llm_features_enabled: "1" } }
      expect(response).to have_http_status(:not_found)
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

      it "offers no tabs while the connection is disabled" do
        create(:llm_connection, base_url:)

        get llm_connection_path

        expect(response.body).not_to include("llm-settings--tabs")
      end

      it "points at no tab while the connection is disabled" do
        create(:llm_connection, base_url:)

        get llm_connection_path

        expect(response.body).to include("Connect OpenProject to an LLM server")
        expect(response.body).not_to include("review the models offered by the server")
      end

      it "points at the Models tab once the features are on",
         with_settings: { llm_features_enabled: true } do
        create(:llm_connection, base_url:)

        get llm_connection_path

        expect(response.body).to include("review the models offered by the server")
        expect(page).to have_css("a[href='#{llm_models_path}']", text: "Models")
      end

      it "offers the Models and Feature configuration tabs once the features are on",
         with_settings: { llm_features_enabled: true } do
        create(:llm_connection, base_url:)

        get llm_connection_path

        expect(response.body).to include("llm-settings--tabs")
        expect(response.body).to include(llm_models_path)
        expect(response.body).to include(llm_feature_bindings_path)
      end

      context "without a provider" do
        it "offers the features switch and nothing else while it is off" do
          get llm_connection_path

          expect(response).to have_http_status(:ok)
          expect(page).to have_field(features_switch, disabled: false)
          expect(page).to have_button("Save")
          expect(page).to have_no_css(new_provider_button)
        end

        context "with LLMs switched on", with_settings: { llm_features_enabled: true } do
          it "offers to add a provider, with no tabs to lead nowhere yet" do
            get llm_connection_path

            expect(page).to have_field(features_switch, checked: true)
            expect(page).to have_css(new_provider_button)
            expect(page).to have_no_link("Models")
          end
        end
      end

      context "with a stored connection and LLMs switched off", with_settings: { llm_features_enabled: false } do
        before { create(:llm_connection, base_url:) }

        it "still offers to save, so the switch can be turned back on" do
          get llm_connection_path

          expect(page).to have_field(features_switch, disabled: false)
          expect(page).to have_button("Save")
        end

        it "hides the providers until it is" do
          get llm_connection_path

          expect(page).to have_no_css(new_provider_button)
        end
      end

      it "does not render the settings of the provider into the form" do
        create(:llm_connection, base_url:, api_key: "sk-original")

        get llm_connection_path

        expect(response.body).not_to include("sk-original")
        expect(page).to have_no_field("llm_connection[api_key]", visible: :all)
        expect(page).to have_no_field("llm_connection[base_url]", visible: :all)
      end

      context "with a connection that is switched on", with_settings: { llm_features_enabled: true } do
        let!(:connection) { create(:llm_connection, base_url:) }

        it "offers the health checks next to the form" do
          get llm_connection_path

          expect(page).to have_css("[data-test-selector='llm-connection--run-health-checks']")
        end
      end

      # Nothing checks a connection no feature may use, and the scheduled check
      # is switched off with it.
      context "with a connection that is switched off" do
        let!(:connection) { create(:llm_connection, base_url:) }

        it "leaves the health checks out" do
          get llm_connection_path

          expect(page).to have_no_css("[data-test-selector='llm-connection--run-health-checks']")
        end
      end

      it "locks the features switch while the environment sets it" do
        allow(Settings::Definition[:llm_features_enabled]).to receive_messages(writable?: false, value: true)
        create(:llm_connection, base_url:)

        get llm_connection_path

        expect(page).to have_field(features_switch, disabled: true)
        expect(page).to have_no_button("Save")
        expect(response.body).to include("stays locked while the environment sets it")
      end

      context "when the connection comes from the environment" do
        let!(:connection) { create(:llm_connection, :provisioned_from_env, base_url:, api_key: "sk-original") }

        before do
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

          expect(response.body).to include("comes from the environment variables, applied on")
          expect(response.body).to include("the next database seed activates")
          expect(response.body).not_to include("does not come from them")
        end

        it "does not claim the values cannot be edited" do
          get llm_connection_path

          expect(response.body).not_to include("cannot be edited here")
        end

        it "warns once the variables differ from the ones that were applied" do
          LlmConnection.active_connection
                       .update_columns(env_fingerprint: LlmConnection.env_fingerprint("base_url" => "https://old.example/v1"))

          get llm_connection_path

          expect(response.body).to include("have changed since they were applied")
        end

        it "does not warn while the applied variables are still the current ones" do
          LlmConnection.active_connection
                       .update_columns(env_fingerprint: LlmConnection.env_fingerprint("base_url" => base_url))

          get llm_connection_path

          expect(response.body).not_to include("have changed since they were applied")
        end
      end

      context "when the environment configures a connection that was never seeded" do
        before { allow(Setting).to receive(:llm_connection).and_return({ "base_url" => base_url }) }

        it "says that the next seed activates the variables" do
          get llm_connection_path

          expect(response.body).to include("the active provider does not come from them")
          expect(response.body).not_to include("comes from the environment variables")
        end
      end

      context "when the environment configures a connection an administrator saved" do
        before do
          create(:llm_connection, base_url: "https://admin.example/v1")
          allow(Setting).to receive_messages(llm_connection: { "base_url" => base_url },
                                             llm_features_enabled?: true)
        end

        it "leaves the switch unlocked and warns that the next seed activates the variables" do
          get llm_connection_path

          expect(response.body).to include("the active provider does not come from them")
          expect(page).to have_field(features_switch, disabled: false)
          expect(page).to have_button("Save")
        end
      end

      context "when the environment no longer configures a connection it wrote" do
        before do
          create(:llm_connection, :provisioned_from_env, base_url:)
          allow(Setting).to receive(:llm_features_enabled?).and_return(true)
        end

        it "is unlocked again" do
          get llm_connection_path

          expect(response.body).not_to include("comes from the environment variables")
          expect(response.body).not_to include("does not come from them")
          expect(page).to have_field(features_switch, disabled: false)
          expect(page).to have_button("Save")
        end
      end
    end
  end

  describe "PATCH /admin/llm_connection" do
    before { login_as admin }

    context "when the administrator switches LLMs on" do
      before { Setting.llm_features_enabled = false }

      context "with models stored" do
        let!(:connection) { create(:llm_connection, :with_models, base_url:) }
        let!(:models_request) { mock_llm_models_response(base_url) }

        it "switches them on without contacting the server" do
          patch llm_connection_path, params: { llm_connection: { llm_features_enabled: "1" } }

          expect(response).to have_http_status(:see_other)
          expect(Setting.llm_features_enabled?).to be(true)
          expect(flash[:notice]).to eq(I18n.t("admin.llm_connections.update.success"))
          expect(models_request).not_to have_been_made
        end
      end

      # The case that matters for OpenProject's own gateway: chat completions are
      # routed, the model list is not.
      context "without models stored" do
        let!(:connection) { create(:llm_connection, base_url:) }

        it "switches them on and says that no models are stored yet" do
          patch llm_connection_path, params: { llm_connection: { llm_features_enabled: "1" } }

          expect(Setting.llm_features_enabled?).to be(true)
          expect(flash[:warning]).to eq(I18n.t("admin.llm_connections.update.no_models"))
        end
      end

      context "without a provider" do
        it "switches them on, leaving the provider to be added next" do
          patch llm_connection_path, params: { llm_connection: { llm_features_enabled: "1" } }

          expect(response).to have_http_status(:see_other)
          expect(Setting.llm_features_enabled?).to be(true)
          expect(flash[:notice]).to eq(I18n.t("admin.llm_connections.update.success"))
          expect(LlmConnection.count).to eq(0)
        end
      end
    end

    context "when the administrator switches LLMs off" do
      let!(:connection) { create(:llm_connection, base_url:, api_key: "sk-test") }

      # Not with_settings:, which stubs Setting.[] and would hide the write.
      before { Setting.llm_features_enabled = true }

      it "confirms that the features are off instead of claiming a connection" do
        patch llm_connection_path, params: { llm_connection: { llm_features_enabled: "0" } }

        expect(Setting.llm_features_enabled?).to be(false)
        expect(flash[:notice]).to eq(I18n.t("admin.llm_connections.update.disabled"))
        expect(flash[:warning]).to be_blank
      end

      it "keeps the provider and its key" do
        patch llm_connection_path, params: { llm_connection: { llm_features_enabled: "0" } }

        expect(connection.reload).to have_attributes(base_url:, api_key: "sk-test")
      end
    end

    context "when the features switch is set through the environment" do
      let!(:connection) { create(:llm_connection, base_url:) }

      before do
        allow(Settings::Definition[:llm_features_enabled]).to receive_messages(writable?: false, value: true)
      end

      it "leaves the switch to the environment and says so" do
        patch llm_connection_path, params: { llm_connection: { llm_features_enabled: "0" } }

        expect(response).to have_http_status(:see_other)
        expect(Setting.llm_features_enabled?).to be(true)
        expect(flash[:error]).to include(I18n.t("settings.errors.not_writable"))
        expect(flash[:notice]).to be_blank
      end

      it "still schedules the health check" do
        allow(Llm::HealthCheckJob).to receive(:toggle_cron_job)

        patch llm_connection_path, params: { llm_connection: { llm_features_enabled: "0" } }

        expect(Llm::HealthCheckJob).to have_received(:toggle_cron_job)
      end
    end

    context "when the connection comes from the environment" do
      let!(:connection) { create(:llm_connection, :provisioned_from_env, base_url:) }

      before do
        Setting.llm_features_enabled = true
        allow(Setting).to receive(:llm_connection).and_return({ "base_url" => base_url })
      end

      it "saves the switch and leaves the connection to the environment" do
        patch llm_connection_path, params: { llm_connection: { llm_features_enabled: "0" } }

        expect(Setting.llm_features_enabled?).to be(false)
        expect(flash[:notice]).to eq(I18n.t("admin.llm_connections.update.disabled"))
        expect(connection.reload).to be_configured_from_env
      end
    end

    it "leaves the server settings alone" do
      connection = create(:llm_connection, base_url:, api_key: "sk-original")

      patch llm_connection_path,
            params: { llm_connection: { llm_features_enabled: "1", base_url: "https://elsewhere.example/v1",
                                        api_key: "sk-crafted", inference_provider_id: create(:inference_provider).id } }

      expect(connection.reload).to have_attributes(base_url:, api_key: "sk-original")
    end
  end

  describe "the default models" do
    let!(:connection) { create(:llm_connection, :with_models, base_url: "https://example.com/v1") }

    before { login_as admin }

    it "are chosen on the Models tab, not here" do
      patch llm_connection_path, params: { llm_connection: { default_chat_model_id: "qwen3.6-27b",
                                                             default_embedding_model_id: "bge-m3" } }

      connection.reload
      expect(connection.default_chat_model_id).to be_nil
      expect(connection.default_embedding_model_id).to be_nil
    end
  end
end
