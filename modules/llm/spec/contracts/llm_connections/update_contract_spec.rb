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

RSpec.describe LlmConnections::UpdateContract, :check_errors_i18n, :llm_server_helpers, :webmock do
  include_context "ModelContract shared context"

  let(:current_user) { build_stubbed(:admin) }
  let(:base_url) { "https://example.com/v1" }
  let(:connection) { LlmConnection.current }
  let(:contract) { described_class.new(connection, current_user) }

  let!(:models_request) { mock_llm_models_response(base_url) }

  context "when only the features switch changed" do
    before { connection.llm_features_enabled = true }

    include_examples "contract is valid"

    it "does not contact the server" do
      contract.validate

      expect(models_request).not_to have_been_made
    end
  end

  describe "the lock while the environment configures the connection" do
    before { allow(Setting).to receive(:llm_connection).and_return({ "base_url" => base_url }) }

    context "when the environment has not written the connection yet" do
      include_examples "contract is valid"
    end

    context "when the environment has written the connection" do
      before { connection.update_columns(env_provisioned_at: Time.current) }

      include_examples "contract is invalid", base: :configured_via_env
    end

    context "when the environment wrote the connection after this save loaded it" do
      before { LlmConnection.where(id: connection.id).update_all(env_provisioned_at: Time.current) }

      include_examples "contract is invalid", base: :configured_via_env
    end
  end

  context "when the save marks the connection as written by the environment" do
    before { connection.env_provisioned_at = Time.current }

    include_examples "contract is invalid", env_provisioned_at: :error_readonly
  end

  describe "default model selection" do
    let(:provider) { create(:inference_provider, :with_models, base_url:) }

    context "with a model the server offers" do
      before { connection.default_chat_model = provider.models.find_by(external_id: "bge-m3") }

      include_examples "contract is valid"
    end

    context "with a model the server does not offer" do
      before { connection.default_chat_model_id = LlmModel.maximum(:id).to_i + 1 }

      include_examples "contract is invalid", default_chat_model_id: :not_available
    end

    context "with a model the server says is an embedding model" do
      before do
        create(:llm_capability_verdict, inference_provider: provider, model_id: "bge-m3", capability: "embeddings",
                                        state: "supported", source: "probe")
        connection.default_chat_model = provider.models.find_by(external_id: "bge-m3")
      end

      include_examples "contract is invalid", default_chat_model_id: :cannot_chat
    end

    context "with an embedding model the server has ruled out" do
      before do
        create(:llm_capability_verdict, inference_provider: provider, model_id: "qwen3.6-27b", capability: "embeddings",
                                        state: "unsupported", source: "probe")
        connection.default_embedding_model = provider.models.find_by(external_id: "qwen3.6-27b")
      end

      include_examples "contract is invalid", default_embedding_model_id: :cannot_embed
    end

    context "with an embedding model nothing has ruled out" do
      before { connection.default_embedding_model = provider.models.find_by(external_id: "qwen3.6-27b") }

      include_examples "contract is valid"
    end

    context "with a stored default the server has since withdrawn" do
      before do
        withdrawn_model = create(:llm_model, :withdrawn, inference_provider: provider)
        connection.update_columns(default_chat_model_id: withdrawn_model.id)
        connection.llm_features_enabled = true
      end

      it "still accepts an unrelated change" do
        expect(connection.changed).not_to include("default_chat_model_id")
        expect_contract_valid
      end
    end
  end
end
