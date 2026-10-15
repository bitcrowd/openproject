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
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
#
# See COPYRIGHT and LICENSE files for more details.
#++

module LlmConnections
  module SemanticIndexes
    class RowComponent < OpPrimer::BorderBoxRowComponent
      alias_method :semantic_index, :model

      def row_data
        { test_selector: "llm-semantic-index--row-#{semantic_index.id}" }
      end

      def title
        safe_join(
          [
            render(Primer::Beta::Text.new(font_weight: :bold, font_size: active? ? 4 : nil)) { semantic_index.title },
            description
          ].compact
        )
      end

      delegate :model_id, :context_token_length, :embedding_vector_dimensions, to: :semantic_index

      STATE_LABEL_SCHEMES = {
        "not_indexed" => :secondary,
        "indexing" => :attention,
        "ready" => :accent,
        "failed" => :danger
      }.freeze

      def column_css_class(column)
        return "#{super} -no-ellipsis" if column == :status

        super
      end

      def status
        safe_join(
          [
            render(Primer::Beta::Label.new(scheme: STATE_LABEL_SCHEMES.fetch(semantic_index.state))) do
              I18n.t("admin.semantic_indexes.states.#{semantic_index.state}")
            end,
            error_message
          ].compact
        )
      end

      def button_links
        [activation, action_menu].compact
      end

      private

      def active? = table.active

      def activation
        if active?
          active_marker
        elsif semantic_index.ready?
          activate_button
        end
      end

      def active_marker
        render(Primer::Beta::Label.new(size: :large, classes: "op-semantic-index-active-card--marker",
                                       test_selector: "llm-semantic-index--active-marker")) do
          safe_join([render(Primer::Beta::Octicon.new(icon: :check, mr: 1)), I18n.t("admin.semantic_indexes.active")])
        end
      end

      def activate_button
        render(
          Primer::Beta::Button.new(
            size: :small,
            tag: :a,
            href: activation_dialog_semantic_index_path(semantic_index),
            data: { controller: "async-dialog" },
            test_selector: "llm-semantic-index--activate-#{semantic_index.id}"
          )
        ) { I18n.t("admin.semantic_indexes.activate.button") }
      end

      def description
        return if semantic_index.description.blank?

        render(Primer::Beta::Text.new(tag: :div, color: :subtle, font_size: :small, classes: "ellipsis")) do
          semantic_index.description
        end
      end

      def error_message
        return unless semantic_index.failed? && semantic_index.error_message.present?

        render(Primer::Beta::Text.new(tag: :div, color: :danger, font_size: :small, mt: 1)) do
          semantic_index.error_message
        end
      end

      def action_menu
        render(Primer::Alpha::ActionMenu.new(anchor_align: :end,
                                             test_selector: "llm-semantic-index--menu-#{semantic_index.id}")) do |menu|
          menu.with_show_button(icon: "kebab-horizontal", "aria-label": I18n.t(:label_more), scheme: :invisible)

          start_indexing_item(menu) if semantic_index.indexable?
          edit_item(menu)
          menu.with_divider
          active? ? locked_delete_item(menu) : delete_item(menu)
        end
      end

      def start_indexing_item(menu)
        menu.with_item(
          label: I18n.t("admin.semantic_indexes.menu.#{semantic_index.failed? ? 'retry_indexing' : 'start_indexing'}"),
          href: start_indexing_semantic_index_path(semantic_index),
          form_arguments: { method: :post }
        ) do |item|
          item.with_leading_visual_icon(icon: :play)
        end
      end

      def edit_item(menu)
        menu.with_item(
          label: I18n.t(semantic_index.parameters_locked? ? "admin.semantic_indexes.menu.edit_locked" : :button_edit),
          tag: :a,
          href: edit_dialog_semantic_index_path(semantic_index),
          content_arguments: { data: { controller: "async-dialog" } }
        ) do |item|
          item.with_leading_visual_icon(icon: :pencil)
        end
      end

      def locked_delete_item(menu)
        menu.with_item(label: I18n.t("admin.semantic_indexes.menu.delete"), scheme: :danger, disabled: true) do |item|
          item.with_leading_visual_icon(icon: :trash)
          item.with_description { I18n.t("admin.semantic_indexes.menu.locked_while_active") }
        end
      end

      def delete_item(menu)
        menu.with_item(
          label: I18n.t("admin.semantic_indexes.menu.delete"),
          scheme: :danger,
          tag: :a,
          href: deletion_dialog_semantic_index_path(semantic_index),
          disabled: semantic_index.indexing?,
          content_arguments: { data: { controller: "async-dialog" } }
        ) do |item|
          item.with_leading_visual_icon(icon: :trash)
        end
      end
    end
  end
end
