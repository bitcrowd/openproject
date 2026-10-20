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
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
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
        raise Llm::Errors::ConfigurationError, "no active connection" if connection.nil?

        result = session.embed(texts,
                               model: semantic_index.model_id,
                               dimensions: semantic_index.embedding_vector_dimensions)

        store(result.vectors)
      end

      private

      attr_reader :semantic_index, :work_packages

      def connection
        @connection ||= LlmConnection.active_connection
      end

      def session = Llm::Session.for(connection)

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

        WorkPackageEmbedding.upsert_all(rows, unique_by: %i[semantic_index_id work_package_id])
      end
    end
  end
end
