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

RSpec.describe InferenceProvider do
  describe "#api_key", with_config: { "database_cipher_key" => "secret" } do
    it "is stored as it was given, even with a cipher key configured" do
      provider = create(:inference_provider, api_key: "sk-plain-key")

      expect(provider.reload.api_key).to eq("sk-plain-key")
      expect(described_class.where(id: provider.id).pick(:api_key)).to eq("sk-plain-key")
    end
  end

  describe "#api_key_stored?" do
    it "is false for a provider that was never saved" do
      expect(build(:inference_provider, api_key: "sk-test-key")).not_to be_api_key_stored
    end

    it "is false for a saved provider without a key" do
      expect(create(:inference_provider, api_key: nil)).not_to be_api_key_stored
    end

    it "is true for a saved provider with a key" do
      expect(create(:inference_provider, api_key: "sk-test-key")).to be_api_key_stored
    end

    it "is false when a key was assigned but the save failed" do
      provider = create(:inference_provider, api_key: nil)
      provider.assign_attributes(api_key: "sk-test-key", base_url: "")

      expect(provider.save).to be(false)
      expect(provider).not_to be_api_key_stored
    end
  end

  describe "#active?" do
    it "is true for the provider of the active connection" do
      expect(create(:llm_connection).inference_provider).to be_active
    end

    it "is false for a provider of an inactive connection" do
      expect(create(:llm_connection, active: false).inference_provider).not_to be_active
    end

    it "is false for a provider no connection points at" do
      create(:llm_connection)

      expect(create(:inference_provider)).not_to be_active
    end
  end

  describe "#base_url" do
    it "loses surrounding whitespace and one trailing slash" do
      expect(build(:inference_provider, base_url: " https://example.com/v1/ ").base_url).to eq("https://example.com/v1")
    end

    it "keeps the path as it was given" do
      expect(build(:inference_provider, base_url: "https://example.com").base_url).to eq("https://example.com")
    end

    it "is found by the same value it was normalized from" do
      provider = create(:inference_provider, base_url: "https://example.com/v1")

      expect(described_class.where(base_url: "https://example.com/v1/")).to contain_exactly(provider)
    end
  end

  describe "#host_and_port" do
    it "leaves out a port the scheme implies" do
      expect(build(:inference_provider, base_url: "https://example.com/v1").host_and_port).to eq("example.com")
      expect(build(:inference_provider, base_url: "http://example.com:80/v1").host_and_port).to eq("example.com")
    end

    it "names any other port" do
      expect(build(:inference_provider, base_url: "http://localhost:11434/v1").host_and_port).to eq("localhost:11434")
    end

    it "gives away neither the userinfo nor the query string" do
      provider = build(:inference_provider, base_url: "https://user:secret@example.com/v1?key=secret")

      expect(provider.host_and_port).to eq("example.com")
    end

    it "is nil without a usable URL", :aggregate_failures do
      ["", nil, "not a url"].each do |base_url|
        expect(build(:inference_provider, base_url:).host_and_port).to be_nil, base_url.inspect
      end
    end
  end

  describe "#base_url_without_credentials" do
    it "gives away neither the userinfo nor the query string" do
      provider = build(:inference_provider, base_url: "https://user:secret@example.com:8443/v1?key=secret#frag")

      expect(provider.base_url_without_credentials).to eq("https://example.com:8443/v1")
    end

    it "is nil for a URL that cannot be parsed" do
      expect(build(:inference_provider, base_url: "not a url").base_url_without_credentials).to be_nil
    end
  end

  it "cannot be destroyed while a connection points at it" do
    provider = create(:llm_connection).inference_provider

    expect(provider.destroy).to be(false)
    expect(described_class.exists?(provider.id)).to be(true)
  end

  it "can be handed to a session as it is" do
    provider = build(:inference_provider, api_format: "openai")

    expect(Llm::Session.for(provider).provider).to eq(:openai)
  end

  # The environment seeder and direct writes reach the model without the
  # contract, so these have to hold on the model itself.
  describe "validations" do
    it "requires a title" do
      provider = build(:inference_provider, title: "")

      expect(provider).not_to be_valid
      expect(provider.errors).to be_of_kind(:title, :blank)
    end

    it "does not ask for a title, which defaults to the host, while the URL is unusable" do
      provider = build(:inference_provider, title: "", base_url: "not a url")

      expect(provider).not_to be_valid
      expect(provider.errors).not_to include(:title)
    end

    it "requires a base URL" do
      provider = build(:inference_provider, base_url: "")

      expect(provider).not_to be_valid
      expect(provider.errors).to be_of_kind(:base_url, :blank)
    end

    it "refuses a format no adapter serves" do
      provider = build(:inference_provider, api_format: "no-such-format")

      expect(provider).not_to be_valid
      expect(provider.errors).to be_of_kind(:api_format, :inclusion)
    end

    it "accepts custom headers that map names to plain strings" do
      expect(build(:inference_provider, custom_headers: { "api-version" => "2024-02-01" })).to be_valid
    end

    it "refuses a header value that is not a string" do
      provider = build(:inference_provider, custom_headers: { "x-retries" => 3 })

      expect(provider).not_to be_valid
      expect(provider.errors).to be_of_kind(:custom_headers, :invalid)
    end

    it "refuses a nested header value" do
      expect(build(:inference_provider, custom_headers: { "x-gateway" => { "key" => "value" } })).not_to be_valid
    end

    it "refuses a header value carrying a line break" do
      expect(build(:inference_provider, custom_headers: { "x-gateway" => "one\r\nInjected: two" })).not_to be_valid
    end

    it "refuses a header name carrying a line break" do
      provider = build(:inference_provider, custom_headers: { "x-gateway\r\nInjected" => "two" })

      expect(provider).not_to be_valid
      expect(provider.errors).to be_of_kind(:custom_headers, :invalid)
    end

    it "refuses a header name that is not an HTTP token", :aggregate_failures do
      ["x gateway", "x-gateway:", "x-gäteway", "(x-gateway)", ""].each do |name|
        expect(build(:inference_provider, custom_headers: { name => "value" })).not_to be_valid, name.inspect
      end
    end

    it "accepts a header name built from any HTTP token character" do
      expect(build(:inference_provider, custom_headers: { "X-Gateway_1.v2!\#$%&'*+^`|~" => "value" })).to be_valid
    end

    it "accepts an absolute http or https base URL", :aggregate_failures do
      %w[https://example.com/v1 http://10.0.0.5:8000/v1].each do |base_url|
        expect(build(:inference_provider, base_url:)).to be_valid, base_url
      end
    end

    it "refuses a base URL without an http scheme or a host", :aggregate_failures do
      %w[//host/path http:host http:// localhost:8080/v1 ftp://example.com].each do |base_url|
        provider = build(:inference_provider, base_url:)

        expect(provider).not_to be_valid, base_url
        expect(provider.errors).to be_of_kind(:base_url, :invalid_url)
      end
    end

    it "refuses a base URL that cannot be parsed" do
      provider = build(:inference_provider, base_url: "https://example.com/a b")

      expect(provider).not_to be_valid
      expect(provider.errors).to be_of_kind(:base_url, :invalid_url)
    end
  end
end
