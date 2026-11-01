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

class PointSemanticIndexesAtEmbeddingModels < ActiveRecord::Migration[8.1]
  class MigrationConnection < ApplicationRecord
    self.table_name = "llm_connections"
  end

  class MigrationProvider < ApplicationRecord
    self.table_name = "inference_providers"
  end

  class MigrationEmbeddingModel < ApplicationRecord
    self.table_name = "embedding_models"
  end

  class MigrationSemanticIndex < ApplicationRecord
    self.table_name = "semantic_indexes"
  end

  def up
    add_reference :semantic_indexes, :embedding_model, foreign_key: { on_delete: :restrict }

    MigrationSemanticIndex.reset_column_information
    backfill

    change_column_null :semantic_indexes, :embedding_model_id, false
    remove_column :semantic_indexes, :model_id
  end

  def down
    add_column :semantic_indexes, :model_id, :string, limit: 512

    execute <<~SQL.squish
      UPDATE semantic_indexes
      SET model_id = embedding_models.external_id
      FROM embedding_models
      WHERE semantic_indexes.embedding_model_id = embedding_models.id
    SQL

    change_column_null :semantic_indexes, :model_id, false
    remove_reference :semantic_indexes, :embedding_model, foreign_key: { on_delete: :restrict }
  end

  private

  # An existing index records neither its server nor anything to verify its model
  # against, and a migration must not contact the LLM server. So this assumes the
  # server the connection points at now is the one that built the vectors.
  def backfill
    return unless MigrationSemanticIndex.exists?

    provider = MigrationProvider.find(active_connection.inference_provider_id)

    MigrationSemanticIndex.find_each do |semantic_index|
      semantic_index.update_columns(embedding_model_id: embedding_model_for(provider, semantic_index).id)
    end
  end

  def active_connection
    MigrationConnection.find_by(active: true) ||
      raise("Semantic indexes exist, but there is no active LLM connection to point them at. " \
            "Configure a connection or delete the semantic indexes, then run the migration again.")
  end

  def embedding_model_for(provider, semantic_index)
    MigrationEmbeddingModel
      .create_with(name: "#{semantic_index.model_id} @ #{provider.title}")
      .find_or_create_by!(inference_provider_id: provider.id,
                          external_id: semantic_index.model_id,
                          context_token_length: semantic_index.context_token_length,
                          embedding_vector_dimensions: semantic_index.embedding_vector_dimensions)
  end
end
