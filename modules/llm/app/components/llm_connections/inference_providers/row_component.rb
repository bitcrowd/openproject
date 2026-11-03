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

      # The scheduled check runs unattended, so this is what shows a server that
      # stopped working without anybody opening the report.
      def health
        step = table.activity.for(inference_provider)
        return busy(step) if step

        health_status
      end

      def button_links = [action_menu]

      private

      def health_status
        report = inference_provider.latest_health_report
        return render(Primer::Beta::Text.new(color: :muted)) { I18n.t("admin.inference_providers.health.never") } if report.nil?

        safe_join([health_label(report.tally), checked_at(report)], " ")
      end

      def health_label(tally)
        scheme, text = health_summary(tally)

        render(Primer::Beta::Label.new(scheme:, test_selector: "llm-inference-provider--health-#{inference_provider.id}")) { text }
      end

      def checked_at(report)
        render(
          Primer::Beta::Link.new(href: inference_provider_health_status_report_path(inference_provider),
                                 scheme: :secondary, font_size: :small, ml: 1, classes: "no-wrap",
                                 test_selector: "llm-inference-provider--checked-at-#{inference_provider.id}")
        ) { helpers.format_time(report.created_at, format: "%H:%M") }
      end

      def busy(step)
        render(Primer::Box.new(test_selector: "llm-inference-provider--activity-#{inference_provider.id}")) do
          safe_join(
            [
              render(Primer::Beta::Spinner.new(size: :small, mr: 1, vertical_align: :middle)),
              I18n.t(step, scope: "admin.inference_providers.health")
            ]
          )
        end
      end

      def health_summary(tally)
        case tally
        in { failure: 1.. }
          [:danger, I18n.t("admin.inference_providers.health.failures", count: tally[:failure])]
        in { warning: 1.. }
          [:attention, I18n.t("admin.inference_providers.health.warnings", count: tally[:warning])]
        else
          [:success, I18n.t("admin.inference_providers.health.healthy")]
        end
      end

      def action_menu
        render(Primer::Alpha::ActionMenu.new(anchor_align: :end,
                                             test_selector: "llm-inference-provider--menu-#{inference_provider.id}")) do |menu|
          menu.with_show_button(icon: "kebab-horizontal", "aria-label": I18n.t(:label_more), scheme: :invisible, size: :small)

          edit_item(menu)
          delete_api_key_item(menu) if inference_provider.api_key_stored?
          menu.with_divider
          run_health_check_item(menu)
          results_item(menu)
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

      def run_health_check_item(menu)
        menu.with_item(
          label: I18n.t("admin.inference_providers.menu.run_health_check"),
          href: check_inference_provider_health_status_report_path(inference_provider),
          form_arguments: { method: :post },
          content_arguments: { test_selector: "llm-inference-provider--run-health-check-#{inference_provider.id}" }
        ) do |item|
          item.with_leading_visual_icon(icon: :pulse)
        end
      end

      def results_item(menu)
        menu.with_item(
          label: I18n.t("admin.inference_providers.menu.results"),
          tag: :a,
          href: inference_provider_health_status_report_path(inference_provider),
          content_arguments: { test_selector: "llm-inference-provider--results-#{inference_provider.id}" }
        ) do |item|
          item.with_leading_visual_icon(icon: :checklist)
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
