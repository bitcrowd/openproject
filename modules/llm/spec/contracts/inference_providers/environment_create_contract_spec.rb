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

RSpec.describe InferenceProviders::EnvironmentCreateContract, :check_errors_i18n, :llm_server_helpers, :webmock do
  include_context "ModelContract shared context"

  let(:current_user) { User.system }
  let(:base_url) { "https://example.com/v1" }
  let(:provider) { build(:inference_provider, base_url:, custom_headers: { "api-version" => "2024-02-01" }) }
  let(:contract) { described_class.new(provider, current_user) }

  let!(:models_request) { mock_llm_models_response(base_url, timeout: true) }

  include_examples "contract is valid"

  it "does not contact the server, which may well start after the seed" do
    contract.validate

    expect(models_request).not_to have_been_made
  end

  context "with a format whose credentials cannot be stored" do
    let(:provider) { build(:inference_provider, api_format: "bedrock", base_url:) }

    include_examples "contract is invalid", api_format: :exclusion
  end

  context "with a base URL that is not a URL at all" do
    let(:base_url) { "not a url" }

    include_examples "contract is invalid", base_url: :invalid_url
  end
end
