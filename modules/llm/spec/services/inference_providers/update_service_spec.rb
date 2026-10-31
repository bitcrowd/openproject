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

RSpec.describe InferenceProviders::UpdateService, :llm_server_helpers, :webmock do
  subject(:result) { described_class.new(user: create(:admin), model: provider).call(params) }

  let(:base_url) { "https://example.com/v1" }
  let(:params) { { api_key: "sk-rotated" } }
  let(:provider) { create(:inference_provider, base_url:, api_key: "sk-original", title: "My gateway") }

  before { mock_llm_models_response(base_url) }

  it "stores the new key" do
    expect(result).to be_success

    expect(provider.reload.api_key).to eq("sk-rotated")
  end

  context "without a title" do
    let(:params) { { title: "" } }

    it "falls back to the host and port" do
      expect(result).to be_success

      expect(provider.reload.title).to eq("example.com")
    end
  end

  context "when the server rejects the new key" do
    before { mock_llm_models_response(base_url, response_code: 401) }

    it "keeps the previous one" do
      expect(result).to be_failure

      expect(provider.reload.api_key).to eq("sk-original")
    end
  end

  context "with the active provider, which the environment wrote" do
    let!(:connection) do
      create(:llm_connection, :provisioned_from_env, base_url:, api_key: "sk-original", env_fingerprint: "applied")
    end
    let(:provider) { connection.inference_provider }

    before { allow(Setting).to receive(:llm_connection).and_return({ "base_url" => base_url }) }

    it "stores the new key and lets go of the environment's marks" do
      expect(result).to be_success

      expect(provider.reload.api_key).to eq("sk-rotated")
      expect(connection.reload).to have_attributes(env_provisioned_at: nil, env_fingerprint: nil)
    end

    context "when only the title changes" do
      let(:params) { { title: "Renamed" } }

      it "keeps the marks, since the values are still the environment's" do
        expect(result).to be_success

        expect(connection.reload).to have_attributes(env_provisioned_at: be_present, env_fingerprint: "applied")
      end
    end

    context "when the server rejects the new key" do
      before { mock_llm_models_response(base_url, response_code: 401) }

      it "keeps the marks" do
        expect(result).to be_failure

        expect(connection.reload).to have_attributes(env_provisioned_at: be_present, env_fingerprint: "applied")
      end
    end
  end

  context "with a stored provider, while the environment wrote the active one" do
    let!(:connection) { create(:llm_connection, :provisioned_from_env, env_fingerprint: "applied") }

    it "keeps the marks" do
      expect(result).to be_success

      expect(connection.reload).to have_attributes(env_provisioned_at: be_present, env_fingerprint: "applied")
    end
  end
end
