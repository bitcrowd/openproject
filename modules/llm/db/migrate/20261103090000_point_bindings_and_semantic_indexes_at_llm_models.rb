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

class PointBindingsAndSemanticIndexesAtLlmModels < ActiveRecord::Migration[8.1]
  class MigrationConnection < ApplicationRecord
    self.table_name = "llm_connections"
  end

  class MigrationModel < ApplicationRecord
    self.table_name = "llm_models"
  end

  class MigrationBinding < ApplicationRecord
    self.table_name = "llm_feature_bindings"
  end

  class MigrationSemanticIndex < ApplicationRecord
    self.table_name = "semantic_indexes"
  end

  def up
    add_reference :llm_feature_bindings, :llm_model, foreign_key: { on_delete: :restrict }
    add_reference :semantic_indexes, :llm_model, foreign_key: { on_delete: :restrict }

    MigrationBinding.reset_column_information
    MigrationSemanticIndex.reset_column_information
    fill_bindings
    fill_semantic_indexes

    change_column_null :semantic_indexes, :llm_model_id, false
    remove_column :llm_feature_bindings, :model_id
    remove_column :semantic_indexes, :model_id
  end

  def down
    add_column :llm_feature_bindings, :model_id, :string
    add_column :semantic_indexes, :model_id, :string, limit: 512

    %w[llm_feature_bindings semantic_indexes].each do |table|
      execute <<~SQL.squish
        UPDATE #{table}
        SET model_id = llm_models.external_id
        FROM llm_models
        WHERE #{table}.llm_model_id = llm_models.id
      SQL
    end

    change_column_null :semantic_indexes, :model_id, false
    remove_reference :llm_feature_bindings, :llm_model, foreign_key: { on_delete: :restrict }
    remove_reference :semantic_indexes, :llm_model, foreign_key: { on_delete: :restrict }
  end

  private

  def fill_bindings
    MigrationBinding.where.not(model_id: [nil, ""]).find_each do |binding|
      binding.update_columns(llm_model_id: model_row_id(binding.llm_connection_id, binding.model_id))
    end
  end

  def fill_semantic_indexes
    return unless MigrationSemanticIndex.exists?

    connection = active_connection

    MigrationSemanticIndex.find_each do |semantic_index|
      semantic_index.update_columns(llm_model_id: model_row_id(connection.id, semantic_index.model_id))
    end
  end

  # An index records nothing about its server, so this assumes the active
  # connection built its vectors. A migration must not contact that server.
  def active_connection
    MigrationConnection.find_by(active: true) ||
      raise("Semantic indexes exist, but there is no active LLM connection to point them at. " \
            "Configure a connection or delete the semantic indexes, then run the migration again.")
  end

  # A name missing from the list stays usable as a model entered by hand, the
  # same way the environment seed records a model it names.
  def model_row_id(connection_id, external_id)
    MigrationModel
      .create_with(manual: true)
      .find_or_create_by!(llm_connection_id: connection_id, external_id:)
      .id
  end
end
