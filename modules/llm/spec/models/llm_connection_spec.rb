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

RSpec.describe LlmConnection do
  describe ".current" do
    it "creates the row when none exists" do
      expect { described_class.current }.to change(described_class, :count).from(0).to(1)
      expect(described_class.current.identifier).to eq(described_class::DEFAULT_IDENTIFIER)
    end

    it "hands out the same row afterwards" do
      first = described_class.current

      expect(described_class.current).to eq(first)
      expect(described_class.count).to eq(1)
    end
  end

  describe ".available?" do
    context "with the feature flag and the setting on",
            with_flag: { llm_connection: true },
            with_settings: { llm_features_enabled: true } do
      it "is true once a provider is stored" do
        create(:inference_provider)

        expect(described_class).to be_available
      end

      it "is false while no provider is stored" do
        described_class.current

        expect(described_class).not_to be_available
      end
    end

    it "is false with the feature flag off",
       with_flag: { llm_connection: false },
       with_settings: { llm_features_enabled: true } do
      create(:inference_provider)

      expect(described_class).not_to be_available
    end

    it "is false with the setting off",
       with_flag: { llm_connection: true },
       with_settings: { llm_features_enabled: false } do
      create(:inference_provider)

      expect(described_class).not_to be_available
    end
  end

  describe "provisioning from the environment" do
    context "with the environment configuring a connection",
            with_settings: { llm_connection: { "base_url" => "https://example.com/v1" } } do
      it "is pending, not locked, for a connection an administrator saved" do
        connection = create(:llm_connection)

        expect(connection).not_to be_configured_from_env
        expect(connection).to be_env_pending
      end

      it "is locked once the environment has written the connection" do
        connection = create(:llm_connection, :provisioned_from_env)

        expect(connection).to be_configured_from_env
        expect(connection).not_to be_env_pending
      end

      it "stays locked while the stored marker is only cleared in memory" do
        connection = create(:llm_connection, :provisioned_from_env)
        connection.env_provisioned_at = nil

        expect(connection).to be_configured_from_env
      end
    end

    context "without the environment configuring a connection" do
      it "is neither locked nor pending for a connection the environment once wrote" do
        connection = create(:llm_connection, :provisioned_from_env)

        expect(connection).not_to be_configured_from_env
        expect(connection).not_to be_env_pending
      end

      it "is neither locked nor pending for a connection an administrator saved" do
        connection = create(:llm_connection)

        expect(connection).not_to be_configured_from_env
        expect(connection).not_to be_env_pending
      end
    end
  end

  describe "#env_changed_since_applied?" do
    let(:env) { { "base_url" => "https://example.com/v1", "api_key" => "sk-from-env" } }
    let(:connection) { create(:llm_connection, :provisioned_from_env) }

    before { allow(Setting).to receive(:llm_connection).and_return(env) }

    it "is false while the variables are the ones that were applied" do
      connection.update_columns(env_fingerprint: described_class.env_fingerprint(env))

      expect(connection.reload).not_to be_env_changed_since_applied
    end

    it "is true once a variable differs from what was applied" do
      connection.update_columns(env_fingerprint: described_class.env_fingerprint(env.merge("api_key" => "sk-rotated")))

      expect(connection.reload).to be_env_changed_since_applied
    end

    it "is false for a connection applied before a fingerprint was recorded" do
      expect(connection.env_fingerprint).to be_nil
      expect(connection).not_to be_env_changed_since_applied
    end

    it "is false once the environment no longer configures the connection" do
      connection.update_columns(env_fingerprint: described_class.env_fingerprint(env))
      allow(Setting).to receive(:llm_connection).and_return({})

      expect(connection.reload).not_to be_env_changed_since_applied
    end

    it "does not carry the API key" do
      expect(described_class.env_fingerprint(env)).not_to include("sk-from-env")
    end

    it "does not depend on the order of the variables" do
      expect(described_class.env_fingerprint(env.to_a.reverse.to_h)).to eq(described_class.env_fingerprint(env))
    end

    it "does not depend on how the same custom headers are written" do
      as_hash = env.merge("custom_headers" => { "api-version" => "2", "apikey" => "gateway" })
      reordered = env.merge("custom_headers" => { "apikey" => "gateway", "api-version" => "2" })
      as_json = env.merge("custom_headers" => '{ "apikey": "gateway",  "api-version": "2" }')

      expect(described_class.env_fingerprint(reordered)).to eq(described_class.env_fingerprint(as_hash))
      expect(described_class.env_fingerprint(as_json)).to eq(described_class.env_fingerprint(as_hash))
    end

    it "treats absent and empty custom headers alike" do
      ["", "{}", {}, nil].each do |empty|
        expect(described_class.env_fingerprint(env.merge("custom_headers" => empty)))
          .to eq(described_class.env_fingerprint(env))
      end
    end

    it "changes when a custom header does" do
      one = env.merge("custom_headers" => { "apikey" => "gateway" })
      other = env.merge("custom_headers" => { "apikey" => "rotated" })

      expect(described_class.env_fingerprint(other)).not_to eq(described_class.env_fingerprint(one))
    end
  end

  describe "#env_named_default?" do
    let(:provider) { create(:inference_provider) }
    let(:connection) { create(:llm_connection, :provisioned_from_env) }
    let(:chat_model) { create(:llm_model, :manual, inference_provider: provider) }
    let(:embedding_model) { create(:llm_model, :manual, inference_provider: provider) }
    let(:other_model) { create(:llm_model, :manual, inference_provider: provider) }

    before do
      connection.update_columns(default_chat_model_id: chat_model.id, default_embedding_model_id: embedding_model.id)
    end

    context "with the environment configuring the connection",
            with_settings: { llm_connection: { "base_url" => "https://example.com/v1" } } do
      it "holds for both defaults" do
        expect(connection.env_named_default?(chat_model)).to be(true)
        expect(connection.env_named_default?(embedding_model)).to be(true)
      end

      it "does not hold for any other model" do
        expect(connection.env_named_default?(other_model)).to be(false)
      end

      it "goes by the stored defaults, not by one only assigned" do
        connection.default_chat_model_id = other_model.id

        expect(connection.env_named_default?(chat_model)).to be(true)
        expect(connection.env_named_default?(other_model)).to be(false)
      end

      it "does not hold before the environment has written the connection" do
        connection.update_columns(env_provisioned_at: nil)

        expect(connection.env_named_default?(chat_model)).to be(false)
      end
    end

    it "does not hold once the environment no longer configures the connection" do
      expect(connection.env_named_default?(chat_model)).to be(false)
    end
  end

  describe "validations" do
    it "requires an identifier, rather than failing on the NOT NULL column" do
      connection = build(:llm_connection, identifier: nil)

      expect(connection).not_to be_valid
      expect(connection.errors).to be_of_kind(:identifier, :blank)
    end
  end
end
