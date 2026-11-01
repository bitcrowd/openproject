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

require "rails_helper"
require_module_spec_helper

RSpec.describe LlmConnections::SemanticIndexes::FormComponent, type: :component do
  include Rails.application.routes.url_helpers

  subject(:rendered_component) do
    with_request_url "/admin/llm_feature_bindings" do
      render_inline(described_class.new(semantic_index))
    end
  end

  let(:model_field) { SemanticIndex.human_attribute_name(:embedding_model_id) }

  context "for a new semantic index" do
    let(:semantic_index) { SemanticIndex.new }
    let!(:stored) do
      create(:embedding_model, name: "Large", inference_provider: create(:inference_provider, title: "Ollama"),
                               context_token_length: 2048, embedding_vector_dimensions: 768)
    end

    it "posts to the semantic indexes collection route" do
      rendered_component

      expect(page).to have_css("form[action='#{semantic_indexes_path}'][method='post']")
    end

    it "offers the stored models with their provider" do
      rendered_component

      expect(page).to have_select(model_field, with_options: ["Large @ Ollama"])
    end

    it "hands the numbers of each stored model to the prefill" do
      rendered_component

      defaults = page.find("[data-controller='llm--semantic-index-form']")["data-llm--semantic-index-form-defaults-value"]
      expect(JSON.parse(defaults)).to eq(stored.id.to_s => { "contextLength" => 2048, "dimensions" => 768 })
    end
  end

  context "for a persisted semantic index" do
    let(:semantic_index) { create(:semantic_index, title: "Qwen3 baseline") }

    it "patches the semantic index's own route" do
      rendered_component

      expect(page).to have_css("form[action='#{semantic_index_path(semantic_index)}']")
      expect(page).to have_css("input[name='_method'][value='patch']", visible: :all)
    end

    it "preselects the index's model" do
      rendered_component

      expect(page).to have_select(model_field, selected: semantic_index.embedding_model.name_with_provider)
    end
  end

  context "when the semantic index has been indexed" do
    let(:semantic_index) do
      create(:semantic_index, state: :ready, context_token_length: 2048, embedding_vector_dimensions: 768,
                              embedding_model: create(:embedding_model, name: "Current <b>model</b>",
                                                                        inference_provider: create(:inference_provider,
                                                                                                   title: "Mistral")))
    end
    let(:warning) do
      I18n.t("admin.semantic_indexes.form.locked_once_indexed",
             model: "Current <b>model</b> @ Mistral", context_token_length: 2048, embedding_vector_dimensions: 768)
    end

    before { create(:embedding_model, name: "Another", inference_provider: create(:inference_provider, title: "Ollama")) }

    it "warns which model, context length and dimensions a new model has to be compatible with" do
      rendered_component

      expect(page).to have_text(warning)
      expect(page).to have_no_css("b", text: "model")
    end

    it "keeps naming the current model after a refused change" do
      semantic_index.embedding_model = EmbeddingModel.find_by!(name: "Another")

      rendered_component

      expect(page).to have_text(warning)
    end

    it "locks the numbers, but not the model" do
      rendered_component

      expect(page).to have_field(SemanticIndex.human_attribute_name(:context_token_length), disabled: true)
      expect(page).to have_field(SemanticIndex.human_attribute_name(:embedding_vector_dimensions), disabled: true)
      expect(page).to have_select(model_field, disabled: false, with_options: ["Another @ Ollama"])
    end

    it "does not prefill" do
      rendered_component

      expect(page).to have_no_css("[data-controller='llm--semantic-index-form']")
    end
  end

  context "when the semantic index is being indexed" do
    let(:semantic_index) { create(:semantic_index, state: :indexing) }

    it "locks the model too and says so" do
      rendered_component

      expect(page).to have_text(I18n.t("admin.semantic_indexes.form.locked_while_indexing"))
      expect(page).to have_select(model_field, disabled: true)
    end
  end

  context "with a validation error on the title" do
    let(:semantic_index) { build(:semantic_index, title: "Qwen3 baseline") }

    before { semantic_index.errors.add(:title, :blank) }

    it "still posts to the semantic indexes collection route" do
      rendered_component

      expect(page).to have_css("form[action='#{semantic_indexes_path}'][method='post']")
    end

    it "renders the error message next to the field" do
      rendered_component

      expect(page).to have_text(semantic_index.errors.full_messages_for(:title).first)
    end
  end
end
