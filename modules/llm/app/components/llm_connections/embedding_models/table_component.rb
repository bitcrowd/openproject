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
    class TableComponent < OpPrimer::BorderBoxTableComponent
      columns :name, :external_id, :inference_provider, :context_token_length, :embedding_vector_dimensions

      main_column :name

      mobile_columns :name, :inference_provider

      mobile_labels :inference_provider

      def has_actions? = true

      def has_footer? = false

      def blank_title = I18n.t("admin.embedding_models.box.empty_title")

      def blank_description = I18n.t("admin.embedding_models.box.empty_description")

      def blank_icon = :database

      def mobile_title = I18n.t("admin.embedding_models.box.title")

      def headers
        columns.map { |column| [column, { caption: EmbeddingModel.human_attribute_name(column) }] }
      end
    end
  end
end
