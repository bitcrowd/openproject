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
  module InferenceProviders
    class RowComponent < OpPrimer::BorderBoxRowComponent
      alias_method :inference_provider, :model

      def row_data
        { test_selector: "llm-inference-provider--row-#{inference_provider.id}" }
      end

      def title
        render(Primer::Beta::Text.new(font_weight: :bold)) { inference_provider.title }
      end

      # The userinfo and query string of a URL can carry a credential.
      def base_url = inference_provider.base_url_without_credentials

      def api_format = I18n.t("llm.api_formats.#{inference_provider.api_format}")

      def api_key
        I18n.t(inference_provider.api_key_stored? ? :stored : :none, scope: "admin.inference_providers.api_key")
      end

      def button_links = [action_menu]

      private

      def action_menu
        render(Primer::Alpha::ActionMenu.new(anchor_align: :end,
                                             test_selector: "llm-inference-provider--menu-#{inference_provider.id}")) do |menu|
          menu.with_show_button(icon: "kebab-horizontal", "aria-label": I18n.t(:label_more), scheme: :invisible, size: :small)

          edit_item(menu)
          delete_api_key_item(menu) if inference_provider.api_key_stored?
          menu.with_divider
          delete_item(menu)
        end
      end

      def edit_item(menu)
        menu.with_item(
          label: I18n.t(:button_edit),
          tag: :a,
          href: edit_dialog_inference_provider_path(inference_provider),
          content_arguments: { data: { controller: "async-dialog" } }
        ) do |item|
          item.with_leading_visual_icon(icon: :pencil)
        end
      end

      def delete_api_key_item(menu)
        menu.with_item(
          label: I18n.t("admin.inference_providers.delete_api_key.menu_label"),
          tag: :a,
          href: delete_api_key_dialog_inference_provider_path(inference_provider),
          content_arguments: {
            data: { controller: "async-dialog" },
            test_selector: "llm-inference-provider--delete-api-key-#{inference_provider.id}"
          }
        ) do |item|
          item.with_leading_visual_icon(icon: :key)
        end
      end

      def delete_item(menu)
        menu.with_item(
          label: I18n.t("admin.inference_providers.menu.delete"),
          tag: :a,
          href: deletion_dialog_inference_provider_path(inference_provider),
          scheme: :danger,
          content_arguments: { data: { controller: "async-dialog" } }
        ) do |item|
          item.with_leading_visual_icon(icon: :trash)
        end
      end
    end
  end
end
