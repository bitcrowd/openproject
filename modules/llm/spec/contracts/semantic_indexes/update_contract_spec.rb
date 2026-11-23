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

RSpec.describe SemanticIndexes::UpdateContract do
  include_context "ModelContract shared context"
  include_context "with an embedding model offered"

  let(:semantic_index) { create(:semantic_index) }
  let(:contract) { described_class.new(semantic_index, current_user) }
  let(:current_user) { build_stubbed(:admin) }

  it_behaves_like "contract is valid for active admins and invalid for regular users"

  include_examples "contract reuses the model errors"

  context "when the stored model is no longer offered" do
    before do
      connection.capability_verdicts.destroy_all
      semantic_index.title = "Renamed"
    end

    it_behaves_like "contract is valid"
  end

  context "when renaming or changing description" do
    before do
      semantic_index.title = "Renamed"
      semantic_index.description = "New description"
    end

    it_behaves_like "contract is valid"
  end

  context "when moving the semantic index to another embedding model" do
    let(:other_model) { create(:llm_model, llm_connection: connection, external_id: "bge-m3-elsewhere") }

    before do
      connection.capability_verdicts.create!(model_id: other_model.external_id, capability: "embeddings",
                                             state: "supported", source: "probe", checked_at: Time.current)
      semantic_index.update!(state:)
      semantic_index.llm_model_id = other_model.id
    end

    %w[not_indexed ready failed].each do |allowed_state|
      context "when it is #{allowed_state}" do
        let(:state) { allowed_state }

        it_behaves_like "contract is valid"
      end
    end

    context "when it is indexing" do
      let(:state) { "indexing" }

      it_behaves_like "contract is invalid", llm_model_id: :locked_while_indexing
    end
  end

  context "when moving the semantic index to a chat model" do
    before { semantic_index.llm_model_id = connection.models.find_by!(external_id: "qwen3.6-27b").id }

    it_behaves_like "contract is invalid", llm_model_id: :not_offered
  end

  context "when changing the embedding_vector_dimensions" do
    before { semantic_index.embedding_vector_dimensions = 512 }

    it_behaves_like "contract is invalid", embedding_vector_dimensions: :error_readonly
  end

  context "when changing the context_token_length" do
    before { semantic_index.context_token_length = 4096 }

    it_behaves_like "contract is invalid", context_token_length: :error_readonly
  end
end
