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

module LlmConnections
  # The provider and model selects for one registered feature.
  class FeatureBindingForm < ApplicationForm
    include ModelChoiceFields

    # Primer::Forms::Base.new assigns the builder itself and calls this with the
    # remaining keywords, so the builder must not appear in the signature.
    def initialize(choice:, options:, inherit_label:, feature_key:, models_left_out: false, refreshed: false)
      super()
      @choice = choice
      @model_options = options
      @inherit_label = inherit_label
      @feature_key = feature_key
      @models_left_out = models_left_out
      @refreshed = refreshed
    end

    form do |f|
      provider_autocompleter(f,
                             name: :provider_id,
                             label: InferenceProvider.model_name.human,
                             provider: choice.provider,
                             blank_label: inherit_label,
                             data: { test_selector: "llm-feature-binding--provider-#{feature_key}" })

      model_autocompleter(f) if choice.provider
      f.hidden(name: :llm_model_id, value: "") unless choice.provider

      f.submit(
        name: :submit,
        label: I18n.t(:button_save),
        scheme: :secondary,
        data: { test_selector: "llm-feature-binding--submit-#{feature_key}" }
      )
    end

    private

    attr_reader :choice, :model_options, :inherit_label, :feature_key, :models_left_out, :refreshed

    def model_autocompleter(form)
      choice_autocompleter(form,
                           name: :llm_model_id,
                           label: LlmFeatureBinding.human_attribute_name(:llm_model_id),
                           caption: model_caption,
                           options: model_options.map { |option| [option_label(option), option.model] },
                           selected: choice.model,
                           blank_label: inherit_label,
                           focusDirectly: refreshed,
                           data: { test_selector: "llm-feature-binding--model-#{feature_key}" })
    end

    # Says why only a few of the stored models are on offer.
    def model_caption
      I18n.t("admin.llm_feature_bindings.form.model_caption_ruled_out") if models_left_out
    end

    # The bound model stays choosable once it no longer qualifies, so that saving
    # the form again does not blank the binding. The label says what changed.
    def option_label(option)
      return option.model.name if option.qualifies

      I18n.t("admin.llm_feature_bindings.option_unqualified", model: option.model.name)
    end
  end
end
