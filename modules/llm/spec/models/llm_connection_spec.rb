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
  describe "the settings of its provider" do
    it "are read from the provider" do
      provider = create(:inference_provider, base_url: "https://example.com/v1", api_key: "sk-test",
                                             api_format: "openrouter", custom_headers: { "api-version" => "2" })

      expect(build(:llm_connection, inference_provider: provider))
        .to have_attributes(base_url: "https://example.com/v1", api_key: "sk-test",
                            api_format: "openrouter", custom_headers: { "api-version" => "2" })
    end

    # +active_connection+ hands this record out on an instance with no provider.
    it "are empty on an unsaved connection, with the default format" do
      expect(described_class.new)
        .to have_attributes(base_url: nil, api_key: nil, api_format: "openai", custom_headers: nil)
    end
  end

  describe "#release_from_environment!" do
    it "clears the markers even on a connection that no longer passes validation" do
      connection = create(:llm_connection, :provisioned_from_env, env_fingerprint: "applied")
      connection.update_column(:identifier, "")

      connection.release_from_environment!

      expect(connection.reload).to have_attributes(env_provisioned_at: nil, env_fingerprint: nil)
    end
  end

  describe "the single active connection" do
    it "allows only one connection to be active" do
      create(:llm_connection)
      second = build(:llm_connection, active: true)

      expect(second).not_to be_valid
      expect(second.errors).to be_of_kind(:base, :singleton)
    end

    it "allows any number of inactive connections beside it" do
      create(:llm_connection)

      expect(build(:llm_connection, active: false)).to be_valid
    end

    it "is capped by the database as well as the validation" do
      create(:llm_connection)
      second = build(:llm_connection, active: true)

      expect { second.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "hands out the active connection, unsaved when there is none" do
      expect(described_class.active_connection).to be_new_record
      expect(described_class.active_connection).to be_active

      connection = create(:llm_connection)

      expect(described_class.active_connection).to eq(connection)
    end
  end

  describe "#settings_fingerprint" do
    subject(:connection) { build(:llm_connection, base_url: "https://example.com/v1", api_key: "sk-test") }

    it "changes with the API format" do
      expect { connection.inference_provider.api_format = "anthropic" }.to change(connection, :settings_fingerprint)
    end

    it "changes with the host URL" do
      expect { connection.inference_provider.base_url = "https://elsewhere.example/v1" }
        .to change(connection, :settings_fingerprint)
    end

    it "does not change with the API key" do
      expect { connection.inference_provider.api_key = "sk-rotated" }.not_to change(connection, :settings_fingerprint)
    end

    it "stays the same for another provider on the same server" do
      expect { connection.inference_provider = build(:inference_provider, base_url: "https://example.com/v1") }
        .not_to change(connection, :settings_fingerprint)
    end
  end

  describe "#models_stale?" do
    subject(:connection) { create(:llm_connection, base_url: "https://example.com/v1", api_key: "sk-test") }

    it "is false while no model list has been fetched" do
      expect(connection).not_to be_models_stale
    end

    it "is false while the settings still match the fetched list" do
      connection.update!(connection_fingerprint: connection.settings_fingerprint)

      expect(connection).not_to be_models_stale
    end

    it "is true once the connection points at another server" do
      connection.update!(connection_fingerprint: connection.settings_fingerprint)
      connection.update!(inference_provider: create(:inference_provider, base_url: "https://elsewhere.example/v1"))

      expect(connection).to be_models_stale
    end

    it "stays false when only the API key is rotated" do
      connection.update!(connection_fingerprint: connection.settings_fingerprint)
      connection.inference_provider.update!(api_key: "sk-rotated")

      expect(connection).not_to be_models_stale
    end
  end

  describe "#chat_models" do
    let(:connection) { create(:llm_connection, :with_models) }

    before do
      create(:llm_capability_verdict, llm_connection: connection, model_id: "bge-m3", capability: "embeddings",
                                      state: "supported", source: "probe")
    end

    it "lists the active models that are not embedding models, by identifier" do
      create(:llm_model, llm_connection: connection, external_id: "a-chat-model")
      create(:llm_model, :withdrawn, llm_connection: connection, external_id: "b-withdrawn")

      expect(connection.chat_models.map(&:external_id)).to eq(%w[a-chat-model qwen3.6-27b])
    end

    it "does not query once per model" do
      query_count = -> { ActiveRecord::QueryRecorder.new { connection.chat_models.to_a }.count }
      with_two_models = query_count.call

      create_list(:llm_model, 3, llm_connection: connection)

      expect(query_count.call).to eq(with_two_models)
    end
  end

  describe "#embedding_models" do
    let(:connection) { create(:llm_connection, :with_models) }

    before do
      create(:llm_capability_verdict, llm_connection: connection, model_id: "bge-m3", capability: "embeddings",
                                      state: "supported", source: "probe")
    end

    it "lists the active models that can create embeddings, by identifier" do
      create(:llm_model, :withdrawn, llm_connection: connection, external_id: "a-withdrawn")
      create(:llm_capability_verdict, llm_connection: connection, model_id: "a-withdrawn", capability: "embeddings",
                                      state: "supported", source: "probe")

      expect(connection.embedding_models.map(&:external_id)).to eq(%w[bge-m3])
    end

    it "does not query once per model" do
      query_count = -> { ActiveRecord::QueryRecorder.new { connection.embedding_models.to_a }.count }
      with_two_models = query_count.call

      create_list(:llm_model, 3, llm_connection: connection)

      expect(query_count.call).to eq(with_two_models)
    end
  end

  describe ".available?" do
    context "with the feature flag and the setting on",
            with_flag: { llm_connection: true },
            with_settings: { llm_features_enabled: true } do
      it "is true when an active connection is stored" do
        create(:llm_connection)

        expect(described_class).to be_available
      end

      it "is false when only an inactive connection is stored" do
        create(:llm_connection, active: false)

        expect(described_class).not_to be_available
      end
    end

    it "is false with the feature flag off",
       with_flag: { llm_connection: false },
       with_settings: { llm_features_enabled: true } do
      create(:llm_connection)

      expect(described_class).not_to be_available
    end

    it "is false with the setting off",
       with_flag: { llm_connection: true },
       with_settings: { llm_features_enabled: false } do
      create(:llm_connection)

      expect(described_class).not_to be_available
    end
  end

  describe "provisioning from the environment" do
    context "with the environment configuring a connection",
            with_settings: { llm_connection: { "base_url" => "https://example.com/v1" } } do
      it "is pending, not locked, while no connection is stored" do
        connection = described_class.active_connection

        expect(connection).not_to be_configured_from_env
        expect(connection).to be_env_pending
      end

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
    let(:connection) { create(:llm_connection, :provisioned_from_env) }
    let(:chat_model) { create(:llm_model, :manual, llm_connection: connection) }
    let(:embedding_model) { create(:llm_model, :manual, llm_connection: connection) }
    let(:other_model) { create(:llm_model, :manual, llm_connection: connection) }

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

    it "requires a provider, rather than failing on the NOT NULL column" do
      connection = build(:llm_connection, inference_provider: nil)

      expect(connection).not_to be_valid
      expect(connection.errors).to include(:inference_provider)
    end
  end
end
