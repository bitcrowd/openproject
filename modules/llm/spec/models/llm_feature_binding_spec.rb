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

RSpec.describe LlmFeatureBinding do
  let(:provider) { create(:inference_provider, :with_models) }
  let(:connection) { LlmConnection.current }

  let(:llm_model) { provider.models.find_by!(external_id: "qwen3.6-27b") }

  def bind(llm_model)
    connection.feature_bindings.new(feature_key: "description_assistant", llm_model:)
  end

  describe "the bound model" do
    it "may be one the connection offers" do
      expect(bind(llm_model)).to be_valid
    end

    it "may be left blank to inherit the connection default" do
      expect(bind(nil)).to be_valid
    end

    it "must be one the connection offers" do
      binding = connection.feature_bindings.new(feature_key: "description_assistant",
                                                llm_model_id: LlmModel.maximum(:id).to_i + 1)

      expect(binding).not_to be_valid
      expect(binding.errors.details[:llm_model_id]).to include(error: :not_available)
    end

    it "must not be one an administrator switched off" do
      llm_model.update!(active: false)

      expect(bind(llm_model)).not_to be_valid
    end

    # A catalogue that shrinks underneath a stored binding must not block every
    # later save of it; the page flags the binding as dangling instead.
    it "is not checked again while it stays the same" do
      binding = bind(llm_model).tap(&:save!)
      llm_model.update!(active: false)

      expect(binding.reload).to be_valid
      expect(binding).to be_dangling
    end

    it "reports a missing connection instead of raising" do
      binding = described_class.new(feature_key: "description_assistant", llm_model:)

      expect(binding).not_to be_valid
      expect(binding.errors.details[:llm_connection]).to include(error: :blank)
    end
  end

  describe "inheriting the connection default" do
    let!(:provider) do
      create(:inference_provider, :with_models,
             default_chat_model_identifier: "qwen3.6-27b",
             default_embedding_model_identifier: "bge-m3")
    end

    it "resolves to the default model" do
      binding = bind(nil).tap(&:save!)

      expect(binding.resolved_model).to eq(llm_model)
      expect(binding).not_to be_dangling
    end
  end

  describe "the Semantic Index for an embedding feature" do
    include_context "with an embedding model offered"

    let(:binding) { connection.feature_bindings.new(feature_key: "semantic_search") }

    %w[ready not_indexed indexing failed].each do |state|
      it "may be #{state.humanize(capitalize: false)}" do
        binding.semantic_index = create(:semantic_index, state:)

        expect(binding).to be_valid
      end
    end
  end

  describe "the Semantic Index for a chat feature" do
    include_context "with an embedding model offered"

    it "is rejected" do
      binding = connection.feature_bindings.new(feature_key: "description_assistant",
                                                semantic_index: create(:semantic_index, state: "ready"))

      expect(binding).not_to be_valid
      expect(binding.errors.details[:semantic_index]).to contain_exactly({ error: :not_for_chat_feature })
    end
  end
end
