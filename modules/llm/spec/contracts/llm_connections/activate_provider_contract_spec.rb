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

RSpec.describe LlmConnections::ActivateProviderContract, :check_errors_i18n, :llm_server_helpers, :webmock do
  include_context "ModelContract shared context"

  let(:current_user) { build_stubbed(:admin) }
  let(:provider) { create(:inference_provider, base_url: "https://elsewhere.example/v1") }
  let(:connection) { create(:llm_connection) }
  let(:contract) { described_class.new(connection, current_user) }

  let!(:models_request) { mock_llm_models_response("https://elsewhere.example/v1") }

  before { connection.inference_provider_id = provider.id }

  include_examples "contract is valid"

  it "does not contact the server" do
    contract.validate

    expect(models_request).not_to have_been_made
  end

  context "when the environment has written the connection" do
    let(:connection) { create(:llm_connection, :provisioned_from_env) }

    before { allow(Setting).to receive(:llm_connection).and_return({ "base_url" => "https://example.com/v1" }) }

    include_examples "contract is valid"
  end

  context "with a provider that does not exist" do
    before { connection.inference_provider_id = InferenceProvider.maximum(:id).to_i + 1 }

    include_examples "contract is invalid", inference_provider: :blank
  end
end
