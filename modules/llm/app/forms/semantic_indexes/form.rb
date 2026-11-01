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

module SemanticIndexes
  class Form < ApplicationForm
    def initialize(embedding_models:, locked: false)
      super()
      @embedding_models = embedding_models
      @locked = locked
    end

    form do |f|
      f.text_field(
        name: :title,
        label: SemanticIndex.human_attribute_name(:title),
        required: true,
        autofocus: true
      )

      f.text_area(
        name: :description,
        label: SemanticIndex.human_attribute_name(:description),
        rows: 3
      )

      f.select_list(
        name: :embedding_model_id,
        label: SemanticIndex.human_attribute_name(:embedding_model_id),
        caption: I18n.t("admin.semantic_indexes.form.model_caption"),
        include_blank: I18n.t("admin.semantic_indexes.form.model_prompt"),
        required: true,
        disabled: model.indexing?,
        data: { action: "change->llm--semantic-index-form#prefill", test_selector: "llm-semantic-index--model" }
      ) do |select|
        embedding_models.each do |embedding_model|
          select.option(value: embedding_model.id, label: embedding_model.name_with_provider)
        end
      end

      f.text_field(
        name: :context_token_length,
        type: :number,
        min: 1,
        label: SemanticIndex.human_attribute_name(:context_token_length),
        caption: I18n.t("admin.semantic_indexes.form.context_token_length_caption"),
        required: true,
        disabled: locked,
        input_width: :small,
        data: { "llm--semantic-index-form-target": "contextLength" }
      )

      f.text_field(
        name: :embedding_vector_dimensions,
        type: :number,
        min: 1,
        label: SemanticIndex.human_attribute_name(:embedding_vector_dimensions),
        caption: I18n.t("admin.semantic_indexes.form.embedding_vector_dimensions_caption"),
        required: true,
        disabled: locked,
        input_width: :small,
        data: { "llm--semantic-index-form-target": "dimensions" }
      )
    end

    private

    attr_reader :embedding_models, :locked
  end
end
