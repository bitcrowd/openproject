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
  module SemanticIndexes
    class FormComponent < ApplicationComponent
      include OpPrimer::ComponentHelpers
      include OpTurbo::Streamable

      FORM_ID = "llm-semantic-index-form"

      private

      def locked? = model.parameters_locked?

      def http_method
        model.persisted? ? :patch : :post
      end

      def form_url
        model.persisted? ? semantic_index_path(model) : semantic_indexes_path
      end

      def embedding_models
        @embedding_models ||= EmbeddingModel.for_listing.to_a
      end

      # An indexed Semantic Index keeps its numbers, so picking another model must
      # not touch them.
      def wrapper_data
        return {} if locked?

        { controller: "llm--semantic-index-form", "llm--semantic-index-form-defaults-value": model_defaults.to_json }
      end

      def model_defaults
        embedding_models.to_h do |embedding_model|
          [embedding_model.id, { contextLength: embedding_model.context_token_length,
                                 dimensions: embedding_model.embedding_vector_dimensions }]
        end
      end

      def banner_text
        return t("admin.semantic_indexes.form.locked_while_indexing") if model.indexing?

        t("admin.semantic_indexes.form.locked_once_indexed",
          model: EmbeddingModel.find(model.embedding_model_id_in_database).name_with_provider,
          context_token_length: model.context_token_length_in_database,
          embedding_vector_dimensions: model.embedding_vector_dimensions_in_database)
      end
    end
  end
end
