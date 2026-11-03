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
require "contracts/shared/model_contract_shared_context"

RSpec.describe InferenceProviders::UpdateContract, :check_errors_i18n, :llm_server_helpers, :webmock do
  include_context "ModelContract shared context"

  let(:current_user) { build_stubbed(:admin) }
  let(:base_url) { "https://example.com/v1" }
  let(:provider) { create(:inference_provider, base_url:) }
  let(:contract) { described_class.new(provider, current_user) }

  let!(:models_request) { mock_llm_models_response(base_url) }

  it_behaves_like "contract is valid for active admins and invalid for regular users"

  # Without the changed-attributes guard every unrelated save -- and every form
  # render that builds a model through SetAttributesService -- would fire an
  # outbound request at the LLM server.
  context "with a new title" do
    before { provider.title = "Renamed" }

    include_examples "contract is valid"

    it "does not contact the server" do
      contract.validate

      expect(models_request).not_to have_been_made
    end
  end

  context "with a new API key" do
    before { provider.api_key = "sk-rotated" }

    include_examples "contract is valid"

    it "probes the server exactly once" do
      contract.validate

      expect(models_request).to have_been_made.once
    end

    context "when the server rejects it" do
      let!(:models_request) { mock_llm_models_response(base_url, response_code: 401) }

      include_examples "contract is invalid", api_key: :invalid_api_key

      it "logs the failure by provider, without the URL it probed" do
        logged = []
        allow(Rails.logger).to receive(:info) { |*args, &block| logged << (block ? block.call : args.first) }

        contract.validate

        expect(logged.join).to include("provider #{provider.id}")
        expect(logged.join).not_to include("example.com")
      end
    end
  end

  context "with another base URL, which is another server" do
    before { provider.base_url = "https://elsewhere.example/v1" }

    include_examples "contract is invalid", base_url: :error_readonly
  end

  context "with another API format" do
    before { provider.api_format = "openrouter" }

    include_examples "contract is valid"

    it "checks the server again" do
      contract.validate

      expect(models_request).to have_been_made
    end

    context "when the server does not answer" do
      let!(:models_request) { mock_llm_models_response(base_url, timeout: true) }

      include_examples "contract is invalid", base_url: :request_timed_out
    end
  end

  context "with a format no request can be sent in" do
    before { provider.api_format = "bedrock" }

    include_examples "contract is invalid", api_format: :exclusion
  end

  context "with custom headers, which no form offers" do
    before { provider.custom_headers = { "api-version" => "2024-02-01" } }

    include_examples "contract is invalid", custom_headers: :error_readonly
  end
end
