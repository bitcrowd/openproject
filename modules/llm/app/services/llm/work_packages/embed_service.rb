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

module Llm
  module WorkPackages
    class EmbedService
      def initialize(semantic_index, work_packages)
        @semantic_index = semantic_index
        @work_packages = Array(work_packages)
      end

      def call
        return if work_packages.empty?

        raise Llm::Errors::NotReady, :features_disabled unless LlmConnection.features_enabled?

        vectors = session.embed(texts, model: semantic_index.embedding_model.external_id, dimensions:).vectors
        ensure_requested_dimensions(vectors)

        store(vectors)
      end

      private

      attr_reader :semantic_index, :work_packages

      def session = Llm::Session.for(semantic_index.inference_provider)

      def dimensions = semantic_index.embedding_vector_dimensions

      # Some servers silently ignore the requested size and answer with the model's
      # native one. WorkPackageEmbedding pads every vector, which would hide that.
      def ensure_requested_dimensions(vectors)
        returned = vectors.map(&:length).uniq - [dimensions]
        return if returned.empty?

        raise Llm::Errors::UnexpectedDimensionsError,
              I18n.t("admin.semantic_indexes.indexing.unexpected_dimensions",
                     expected: dimensions, returned: returned.join(", "))
      end

      def texts
        work_packages.map { |wp| EmbeddableText.for(wp, context_window: semantic_index.context_token_length) }
      end

      def store(vectors)
        rows = work_packages.zip(vectors).map do |work_package, vector|
          {
            semantic_index_id: semantic_index.id,
            work_package_id: work_package.id,
            embedding: WorkPackageEmbedding.vector_literal(vector)
          }
        end

        upsert(rows)
      end

      def upsert(rows)
        return if rows.empty?

        WorkPackageEmbedding.transaction(requires_new: true) do
          WorkPackageEmbedding.upsert_all(rows, unique_by: %i[semantic_index_id work_package_id])
        end
      rescue ActiveRecord::InvalidForeignKey
        existing_ids = WorkPackage.where(id: rows.pluck(:work_package_id)).ids
        upsert(rows.select { |row| existing_ids.include?(row[:work_package_id]) })
      end
    end
  end
end
