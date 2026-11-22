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

class PointSemanticIndexesAtLlmModels < ActiveRecord::Migration[8.1]
  class MigrationConnection < ApplicationRecord
    self.table_name = "llm_connections"
  end

  class MigrationModel < ApplicationRecord
    self.table_name = "llm_models"
  end

  class MigrationSemanticIndex < ApplicationRecord
    self.table_name = "semantic_indexes"
  end

  def up
    add_reference :semantic_indexes, :llm_model, foreign_key: { on_delete: :restrict }

    MigrationSemanticIndex.reset_column_information
    fill_semantic_indexes

    change_column_null :semantic_indexes, :llm_model_id, false
    remove_column :semantic_indexes, :model_id
  end

  def down
    add_column :semantic_indexes, :model_id, :string, limit: 512

    execute <<~SQL.squish
      UPDATE semantic_indexes
      SET model_id = llm_models.external_id
      FROM llm_models
      WHERE semantic_indexes.llm_model_id = llm_models.id
    SQL

    change_column_null :semantic_indexes, :model_id, false
    remove_reference :semantic_indexes, :llm_model, foreign_key: { on_delete: :restrict }
  end

  private

  def fill_semantic_indexes
    return unless MigrationSemanticIndex.exists?

    connection = active_connection

    MigrationSemanticIndex.find_each do |semantic_index|
      semantic_index.update_columns(llm_model_id: model_row_id(connection.id, semantic_index.model_id))
    end
  end

  def active_connection
    MigrationConnection.find_by(active: true) ||
      raise("Semantic indexes exist, but there is no active LLM connection to point them at. " \
            "Configure a connection or delete the semantic indexes, then run the migration again.")
  end

  def model_row_id(connection_id, external_id)
    MigrationModel
      .create_with(manual: true, active: false)
      .find_or_create_by!(llm_connection_id: connection_id, external_id:)
      .id
  end
end
