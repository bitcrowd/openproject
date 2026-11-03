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
  # The provider and model selects of one feature, which come back from the
  # server when another provider is picked.
  class FeatureBindingFormComponent < ApplicationComponent
    include ApplicationHelper
    include OpPrimer::ComponentHelpers
    include OpTurbo::Streamable

    def initialize(feature:, connection:, binding: nil, picked_provider_id: nil, refreshed: false)
      super(feature)
      @feature = feature
      @connection = connection
      @binding = binding
      @picked_provider_id = picked_provider_id
      @refreshed = refreshed
    end

    def wrapper_uniq_by = feature.key

    private

    attr_reader :feature, :connection, :binding, :picked_provider_id, :refreshed

    def wrapper_data
      {
        controller: "refresh-on-form-changes",
        "refresh-on-form-changes-turbo-stream-url-value": url_helpers.refresh_form_llm_feature_binding_path(feature.key)
      }
    end

    # The record the select binds to. A feature without a stored binding still
    # needs one so the form has an llm_model_id to read.
    def form_model
      binding || connection.feature_bindings.new(feature_key: feature.key.to_s)
    end

    def choice
      @choice ||= ModelChoice.new(binding&.llm_model_id, picked_provider_id)
    end

    # Not named +options+: ApplicationComponent already owns that name.
    def model_options
      selectable_models&.call.to_a
    end

    def models_left_out? = feature.chat? && selectable_models&.models_left_out?

    def selectable_models
      return if choice.provider.nil?

      @selectable_models ||= SelectableModelsQuery.new(choice.provider, feature, bound_model:)
    end

    def bound_model
      LlmModel.find_by(id: binding&.llm_model_id_in_database)
    end

    def inherit_label
      if default_model
        I18n.t("admin.llm_feature_bindings.inherit_with_default", model: default_model.name_with_provider)
      else
        I18n.t("admin.llm_feature_bindings.inherit_without_default")
      end
    end

    def default_model
      connection.default_model_for(feature)
    end

    def form_url
      url_helpers.llm_feature_binding_path(feature.key)
    end
  end
end
