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
    include LlmConnections::ModelChoiceFields

    def initialize(provider:, selected_model:, model_options:, locked: false, refreshed: false)
      super()
      @provider = provider
      @selected_model = selected_model
      @model_options = model_options
      @locked = locked
      @refreshed = refreshed
    end

    form do |f|
      # Turbo moves focus to an autofocus field after a stream replaced the
      # focused one, which would pull the administrator away from the model select.
      f.text_field(
        name: :title,
        label: SemanticIndex.human_attribute_name(:title),
        required: true,
        autofocus: !refreshed
      )

      f.text_area(
        name: :description,
        label: SemanticIndex.human_attribute_name(:description),
        rows: 3
      )

      f.hidden(name: :prefilled_from_model_id, value: selected_model&.id) unless locked

      provider_autocompleter(f,
                             name: :provider_id,
                             label: InferenceProvider.model_name.human,
                             provider:,
                             clearable: false,
                             disabled: model.indexing?,
                             append_to: dialog_selector,
                             data: { test_selector: "llm-semantic-index--provider" })

      model_autocompleter(f)

      f.text_field(
        name: :context_token_length,
        type: :number,
        min: 1,
        label: SemanticIndex.human_attribute_name(:context_token_length),
        caption: I18n.t("admin.semantic_indexes.form.context_token_length_caption"),
        required: true,
        disabled: locked,
        input_width: :small
      )

      f.text_field(
        name: :embedding_vector_dimensions,
        type: :number,
        min: 1,
        label: SemanticIndex.human_attribute_name(:embedding_vector_dimensions),
        caption: I18n.t("admin.semantic_indexes.form.embedding_vector_dimensions_caption"),
        required: true,
        disabled: locked,
        input_width: :small
      )
    end

    private

    attr_reader :provider, :selected_model, :model_options, :locked, :refreshed

    def dialog_selector = "##{LlmConnections::SemanticIndexes::DialogComponent::DIALOG_ID}"

    def model_autocompleter(form)
      choice_autocompleter(form,
                           name: :llm_model_id,
                           label: SemanticIndex.human_attribute_name(:llm_model_id),
                           caption: I18n.t("admin.semantic_indexes.form.model_caption"),
                           required: true,
                           options: model_options.map { |option| [option_label(option), option.model] },
                           selected: selected_model,
                           disabled: model.indexing?,
                           append_to: dialog_selector,
                           focusDirectly: refreshed,
                           data: { test_selector: "llm-semantic-index--model" },
                           **refresh_on_change)
    end

    # An indexed Semantic Index keeps its numbers, so picking another model has
    # nothing to fill in.
    def refresh_on_change
      locked ? {} : { hiddenFieldAction: REFRESH_ON_CHANGE }
    end

    def option_label(option)
      return option.model.name if option.qualifies

      I18n.t("admin.semantic_indexes.form.option_unqualified", model: option.model.name)
    end
  end
end
