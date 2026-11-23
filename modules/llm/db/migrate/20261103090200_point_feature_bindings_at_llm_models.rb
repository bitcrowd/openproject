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

class PointFeatureBindingsAtLlmModels < ActiveRecord::Migration[8.1]
  class MigrationModel < ApplicationRecord
    self.table_name = "llm_models"
  end

  class MigrationBinding < ApplicationRecord
    self.table_name = "llm_feature_bindings"
  end

  def up
    add_reference :llm_feature_bindings, :llm_model, foreign_key: { on_delete: :restrict }

    MigrationBinding.reset_column_information
    fill_bindings

    remove_column :llm_feature_bindings, :model_id
  end

  def down
    add_column :llm_feature_bindings, :model_id, :string

    execute <<~SQL.squish
      UPDATE llm_feature_bindings
      SET model_id = llm_models.external_id
      FROM llm_models
      WHERE llm_feature_bindings.llm_model_id = llm_models.id
    SQL

    remove_reference :llm_feature_bindings, :llm_model, foreign_key: { on_delete: :restrict }
  end

  private

  # The semantic index decides the model of semantic_search, and no form shows one on its binding.
  def fill_bindings
    MigrationBinding.where.not(model_id: [nil, ""]).where.not(feature_key: "semantic_search").find_each do |binding|
      binding.update_columns(llm_model_id: model_row_id(binding.llm_connection_id, binding.model_id))
    end
  end

  def model_row_id(connection_id, external_id)
    MigrationModel
      .create_with(manual: true, active: false)
      .find_or_create_by!(llm_connection_id: connection_id, external_id:)
      .id
  end
end
