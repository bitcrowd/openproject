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

RSpec.describe InferenceProviders::CreateService, :llm_server_helpers, :webmock do
  subject(:result) { described_class.new(user: create(:admin)).call(params) }

  let(:base_url) { "https://example.com:8443/v1" }
  let(:params) { { base_url:, api_key: "sk-test", api_format: "openai", title: } }
  let(:title) { "My gateway" }

  before { mock_llm_models_response(base_url) }

  it "stores the provider" do
    expect(result).to be_success

    expect(result.result.reload)
      .to have_attributes(title: "My gateway", base_url:, api_key: "sk-test", api_format: "openai")
  end

  it "fetches its model list in the background" do
    expect { result }.to have_enqueued_job(Llm::SyncModelsJob).with(a_kind_of(Integer))
  end

  it "normalizes the URL" do
    mock_llm_models_response("https://example.com:8443/v1")

    result = described_class.new(user: create(:admin)).call(params.merge(base_url: "#{base_url}/ "))

    expect(result.result.base_url).to eq(base_url)
  end

  context "without a title" do
    let(:title) { "" }

    it "defaults to the host and port" do
      expect(result).to be_success

      expect(result.result.title).to eq("example.com:8443")
    end

    it "adds a number when another provider already has that title" do
      create(:inference_provider, title: "example.com:8443")

      expect(result).to be_success

      expect(result.result.title).to eq("example.com:8443 (2)")
    end

    context "with credentials in the URL" do
      let(:base_url) { "https://user:secret@example.com/v1?key=secret" }

      before { stub_request(:get, %r{example\.com/v1}).to_return(status: 200, body: { data: [] }.to_json) }

      it "leaves them out" do
        expect(result).to be_success

        expect(result.result.title).to eq("example.com")
      end
    end

    context "with a URL that is not a URL at all" do
      let(:base_url) { "not a url" }

      it "reports the URL, and not the title that depends on it" do
        expect(result).to be_failure

        expect(result.errors).to be_of_kind(:base_url, :invalid_url)
        expect(result.errors).not_to include(:title)
      end
    end
  end

  context "with a title another provider already has" do
    before { create(:inference_provider, title: "My gateway") }

    it "refuses it" do
      expect(result).to be_failure

      expect(result.errors).to be_of_kind(:title, :taken)
    end
  end

  context "when the server rejects the credentials" do
    before { mock_llm_models_response(base_url, response_code: 401) }

    it "stores nothing" do
      expect(result).to be_failure

      expect(InferenceProvider.count).to eq(0)
    end
  end

  context "with a user who is no administrator" do
    subject(:result) { described_class.new(user: create(:user)).call(params) }

    it "stores nothing" do
      expect(result).to be_failure

      expect(InferenceProvider.count).to eq(0)
    end
  end
end
