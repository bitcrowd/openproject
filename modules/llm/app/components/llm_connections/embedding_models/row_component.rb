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
  module EmbeddingModels
    class RowComponent < OpPrimer::BorderBoxRowComponent
      alias_method :embedding_model, :model

      delegate :external_id, :context_token_length, :embedding_vector_dimensions, to: :embedding_model

      def row_data
        { test_selector: "llm-embedding-model--row-#{embedding_model.id}" }
      end

      def name
        render(Primer::Beta::Text.new(font_weight: :bold)) { embedding_model.name }
      end

      def inference_provider = embedding_model.inference_provider.title

      def button_links
        [action_menu]
      end

      private

      def action_menu
        render(Primer::Alpha::ActionMenu.new(anchor_align: :end,
                                             test_selector: "llm-embedding-model--menu-#{embedding_model.id}")) do |menu|
          menu.with_show_button(icon: "kebab-horizontal", "aria-label": I18n.t(:label_more), scheme: :invisible, size: :small)

          edit_item(menu)
          menu.with_divider
          delete_item(menu)
        end
      end

      def edit_item(menu)
        menu.with_item(
          label: I18n.t(:button_edit),
          tag: :a,
          href: edit_dialog_embedding_model_path(embedding_model),
          content_arguments: { data: { controller: "async-dialog" } }
        ) do |item|
          item.with_leading_visual_icon(icon: :pencil)
        end
      end

      def delete_item(menu)
        menu.with_item(
          label: I18n.t("admin.embedding_models.menu.delete"),
          tag: :a,
          href: deletion_dialog_embedding_model_path(embedding_model),
          scheme: :danger,
          content_arguments: { data: { controller: "async-dialog" } }
        ) do |item|
          item.with_leading_visual_icon(icon: :trash)
        end
      end
    end
  end
end
