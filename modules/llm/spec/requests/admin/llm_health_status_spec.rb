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

RSpec.describe "LLM connection health status", :llm_server_helpers, :skip_csrf, :webmock,
               type: :rails_request, with_flag: { llm_connection: true },
               with_settings: { llm_features_enabled: true } do
  shared_let(:admin) { create(:admin) }

  let(:base_url) { "https://example.com/v1" }
  let(:provider) { create(:inference_provider, :with_models, base_url:) }

  before { login_as(admin) }

  describe "GET /admin/inference_providers/:id/health_status_report" do
    it "is not found for a provider that does not exist" do
      get inference_provider_health_status_report_path(0)

      expect(response).to have_http_status(:not_found)
    end

    context "with a connection" do
      let!(:provider) { create(:inference_provider, :with_models, base_url:) }
      let(:connection) { LlmConnection.current }

      it "offers to run the checks when none have run" do
        get inference_provider_health_status_report_path(provider)

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("has not been checked yet")
      end

      it "names the provider, without being taken for markup" do
        provider.update!(title: "Local <b>Ollama</b>")

        get inference_provider_health_status_report_path(provider)

        expect(response.body).to include("Inference provider: Local &lt;b&gt;Ollama&lt;/b&gt;.")
        expect(response.body).not_to include("<b>Ollama</b>")
      end

      context "with a report on another provider" do
        before do
          group = HealthReport::ResultGroup.new(key: :configuration, results: [HealthReport::Result.success(:enabled)])
          create(:inference_provider).health_reports.create!(results: [group])
        end

        it "offers to run the checks, since this provider has none" do
          get inference_provider_health_status_report_path(provider)

          expect(response.body).to include("has not been checked yet")
          expect(response.body).not_to include("Last checked")
        end
      end

      it "renders the report once it exists" do
        mock_llm_models_response(base_url)
        mock_llm_chat_response(base_url)
        post inference_provider_health_status_report_path(provider)

        get inference_provider_health_status_report_path(provider)

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Configuration")
      end
    end

    it "sends the administrator to the settings while the features are off",
       with_settings: { llm_features_enabled: false } do
      create(:inference_provider, :with_models, base_url:)

      get inference_provider_health_status_report_path(provider)

      expect(response).to redirect_to(llm_connection_path)
      expect(flash[:notice]).to eq(I18n.t("admin.llm_connections.disabled_notice"))
    end
  end

  describe "POST /admin/inference_providers/:id/health_status_report" do
    let!(:provider) { create(:inference_provider, :with_models, base_url:, default_chat_model_identifier: "qwen3.6-27b") }
    let(:connection) { LlmConnection.current }

    before do
      mock_llm_models_response(base_url)
      mock_llm_chat_response(base_url)
    end

    it "refuses to run the checks while the connection is disabled" do
      allow(Setting).to receive(:llm_features_enabled?).and_return(false)

      expect { post inference_provider_health_status_report_path(provider) }
        .not_to change(provider.health_reports, :count)

      expect(response).to redirect_to(llm_connection_path)
      expect(flash[:notice]).to eq(I18n.t("admin.llm_connections.disabled_notice"))
    end

    it "stores a report and sends the completion an administrator asked for" do
      expect { post inference_provider_health_status_report_path(provider) }
        .to change(provider.health_reports, :count).by(1)

      expect(response).to redirect_to(inference_provider_health_status_report_path(provider))
      expect(WebMock).to have_requested(:post, "#{base_url}/chat/completions").once
    end

    it "says what the checks found" do
      post inference_provider_health_status_report_path(provider)

      expect(flash[:notice]).to include("The checks have run")
      expect(flash[:notice]).to match(/\d+ passed/)
    end

    # Without it a second run within the same minute renders an identical page.
    it "counts the results next to the timestamp" do
      post inference_provider_health_status_report_path(provider)

      get inference_provider_health_status_report_path(provider)

      expect(response.body).to include("Last checked")
      expect(response.body).to match(/\d+ passed, \d+ warnings, \d+ failed/)
    end

    it "calls a run with inference a full check" do
      post inference_provider_health_status_report_path(provider)

      get inference_provider_health_status_report_path(provider)

      expect(response.body).to include("Full check, including an inference request.")
    end

    # The scheduled check leaves inference out, and its report can supersede a
    # failed full check, so the page has to say which of the two it shows.
    it "says when the report comes without an inference request" do
      Llm::HealthCheckJob.perform_now

      get inference_provider_health_status_report_path(provider)

      expect(response.body).to include("Checked without an inference request")
    end
  end

  describe "GET /admin/inference_providers/:id/health_status_report.txt" do
    let!(:connection) do
      create(:inference_provider, :with_models, base_url:,
                                                api_key: "sk-super-secret",
                                                custom_headers: { "apikey" => "gateway-secret" })
    end

    before do
      mock_llm_models_response(base_url)
      mock_llm_chat_response(base_url)
      post inference_provider_health_status_report_path(provider)
    end

    it "downloads the report" do
      get inference_provider_health_status_report_path(provider, format: :txt)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("base_url")
    end

    it "names the provider" do
      provider.update!(title: "Local Ollama")

      get inference_provider_health_status_report_path(provider, format: :txt)

      expect(YAML.safe_load(response.body, permitted_classes: [Symbol])).to include("inference_provider" => "Local Ollama")
    end

    it "is plain YAML, without serialized Ruby objects" do
      provider.update_columns(last_synced_at: Time.zone.parse("2026-10-07 14:42:41"))

      get inference_provider_health_status_report_path(provider, format: :txt)

      expect(response.media_type).to eq("text/plain")
      expect(response.headers["Content-Disposition"]).to include(".txt")
      expect(response.body).not_to include("!ruby")

      report = YAML.safe_load(response.body, permitted_classes: [Symbol])
      expect(report["configuration"]).to include("base_url" => base_url, "last_synced_at" => "2026-10-07T14:42:41Z")
      expect(report["configuration"].values).to all(be_nil.or(be_a(String)).or(be_a(Integer)).or(be(true)).or(be(false)))
    end

    # The report is pasted into support tickets. A gateway header routinely
    # carries a second credential, so neither it nor the API key may appear.
    it "contains no credentials" do
      get inference_provider_health_status_report_path(provider, format: :txt)

      expect(response.body).not_to include("sk-super-secret")
      expect(response.body).not_to include("gateway-secret")
    end

    it "strips credentials carried in the base URL" do
      provider.update_column(:base_url, "https://user:url-password@example.com/v1?api-key=query-secret")

      get inference_provider_health_status_report_path(provider, format: :txt)

      expect(response.body).to include("https://example.com/v1")
      expect(response.body).not_to include("url-password")
      expect(response.body).not_to include("query-secret")
    end
  end

  describe "POST /admin/inference_providers/:id/health_status_report/check" do
    let!(:provider) { create(:inference_provider, :with_models, base_url:) }

    def check
      post check_inference_provider_health_status_report_path(provider),
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    it "runs the full check in the background" do
      expect { check }.to have_enqueued_job(Llm::CheckProviderHealthJob).with(provider.id)

      expect(response).to have_http_status(:ok)
      expect(provider.health_reports).to be_empty
    end

    it "has the provider's row say so until the outcome replaces it",
       with_good_job_batches: [Llm::CheckProviderHealthJob] do
      check

      expect(response.body).to include("llm-inference-provider--activity-#{provider.id}", "Running checks…",
                                       "poll-for-changes")
    end

    it "refuses to run the checks while the features are off" do
      allow(Setting).to receive(:llm_features_enabled?).and_return(false)

      expect { check }.not_to have_enqueued_job(Llm::CheckProviderHealthJob)
      expect(response).to redirect_to(llm_connection_path)
    end
  end

  shared_examples "a refused request" do |status|
    it "refuses the page" do
      get inference_provider_health_status_report_path(provider)

      expect(response).to have_http_status(status)
    end

    it "refuses the download" do
      get inference_provider_health_status_report_path(provider, format: :txt)

      expect(response).to have_http_status(status)
    end

    it "refuses to run the checks" do
      expect { post inference_provider_health_status_report_path(provider) }
        .not_to change(HealthReport, :count)

      expect(response).to have_http_status(status)
    end

    it "refuses to run the checks from the list" do
      expect { post check_inference_provider_health_status_report_path(provider) }
        .not_to have_enqueued_job(Llm::CheckProviderHealthJob)

      expect(response).to have_http_status(status)
    end
  end

  describe "authorization" do
    let!(:provider) { create(:inference_provider, :with_models, base_url:) }
    let(:connection) { LlmConnection.current }

    before do
      group = HealthReport::ResultGroup.new(key: :configuration, results: [HealthReport::Result.success(:enabled)])
      provider.health_reports.create!(results: [group])
    end

    context "as a non-admin" do
      before { login_as(create(:user)) }

      it_behaves_like "a refused request", :forbidden
    end

    context "with the feature flag off", with_flag: { llm_connection: false } do
      it_behaves_like "a refused request", :not_found
    end
  end
end
