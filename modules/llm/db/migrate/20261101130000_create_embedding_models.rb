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

class CreateEmbeddingModels < ActiveRecord::Migration[8.1]
  def change
    create_table :embedding_models do |t|
      t.references :inference_provider, null: false, index: false, foreign_key: { on_delete: :restrict }
      t.string :name, null: false
      t.string :external_id, null: false, limit: 512
      t.integer :context_token_length, null: false
      t.integer :embedding_vector_dimensions, null: false

      t.timestamps null: false

      t.index %i[inference_provider_id external_id context_token_length embedding_vector_dimensions],
              unique: true,
              name: "index_embedding_models_on_provider_and_parameters"
    end
  end
end
