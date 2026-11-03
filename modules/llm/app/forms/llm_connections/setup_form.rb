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
  # The settings page while no inference provider exists: switching the AI
  # features on and naming the first server are one save.
  class SetupForm < ApplicationForm
    include InferenceProviders::FormFields

    def initialize(features_enabled:)
      super()
      @features_enabled = features_enabled
    end

    form do |f|
      f.check_box(
        name: :llm_features_enabled,
        label: LlmConnection.human_attribute_name(:llm_features_enabled),
        caption: features_caption,
        value: "1",
        checked: features_enabled,
        disabled: !Setting.llm_features_enabled_writable?,
        scope_name_to_model: false,
        scope_id_to_model: false,
        data: { target_name: "llm_features_enabled", show_when_checked_target: "cause" }
      )

      f.fieldset_group(
        title: I18n.t("admin.llm_connections.form.server_group"),
        hidden: !features_enabled,
        data: {
          target_name: "llm_features_enabled",
          show_when_checked_target: "effect",
          show_when: "checked"
        }
      ) do |server|
        provider_fields(server, autofocus: false)
      end

      # Primer hides an input through a wrapper the toggle cannot reach, so the
      # button carries the class itself.
      f.submit(
        name: :submit,
        label: I18n.t(:button_save),
        scheme: :primary,
        classes: ("d-none" unless features_enabled),
        data: {
          "llm--connection-form-target": "submitButton",
          target_name: "llm_features_enabled",
          show_when_checked_target: "effect",
          show_when: "checked",
          visibility_class: "d-none"
        }
      )
    end

    private

    attr_reader :features_enabled

    def features_caption
      return I18n.t("admin.llm_connections.form.llm_features_enabled_caption_env") unless Setting.llm_features_enabled_writable?

      I18n.t("admin.llm_connections.form.llm_features_enabled_caption")
    end
  end
end
