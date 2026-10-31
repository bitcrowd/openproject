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

class CreateInferenceProviders < ActiveRecord::Migration[8.1]
  class MigrationConnection < ApplicationRecord
    self.table_name = "llm_connections"
  end

  class MigrationProvider < ApplicationRecord
    self.table_name = "inference_providers"
  end

  def up
    create_table :inference_providers do |t|
      t.string :title, null: false
      t.string :base_url, null: false
      # Nullable: an unauthenticated self-hosted server needs no key.
      t.string :api_key
      # Which dialect the server speaks. Only a subset is implemented; the column
      # exists so that adding a format is a new adapter rather than a migration.
      t.string :api_format, null: false, default: "openai"
      # Provider-specific headers sent with every request, e.g. Azure's
      # api-version or a gateway's own key header.
      t.jsonb :custom_headers, null: false, default: {}

      t.timestamps null: false
    end

    add_reference :llm_connections, :inference_provider, foreign_key: { on_delete: :restrict }

    MigrationConnection.reset_column_information
    MigrationProvider.reset_column_information
    MigrationConnection.find_each { |connection| move_settings_to_provider(connection) }

    change_column_null :llm_connections, :inference_provider_id, false
    remove_columns :llm_connections, :base_url, :api_key, :api_format, :custom_headers
  end

  def down
    change_table :llm_connections, bulk: true do |t|
      t.string :base_url
      t.string :api_key
      t.string :api_format, null: false, default: "openai"
      t.jsonb :custom_headers, null: false, default: {}
    end

    MigrationConnection.reset_column_information
    MigrationProvider.reset_column_information
    MigrationConnection.find_each { |connection| restore_settings_from_provider(connection) }

    change_column_null :llm_connections, :base_url, false
    remove_reference :llm_connections, :inference_provider, foreign_key: { on_delete: :restrict }
    drop_table :inference_providers
  end

  private

  def move_settings_to_provider(connection)
    provider = MigrationProvider.create!(title: title_for(connection),
                                         base_url: connection.base_url,
                                         api_key: connection.api_key,
                                         api_format: connection.api_format,
                                         custom_headers: connection.custom_headers)

    connection.update_columns(inference_provider_id: provider.id)
  end

  def restore_settings_from_provider(connection)
    provider = MigrationProvider.find(connection.inference_provider_id)

    connection.update_columns(base_url: provider.base_url,
                              api_key: provider.api_key,
                              api_format: provider.api_format,
                              custom_headers: provider.custom_headers)
  end

  # Host and port only: the userinfo or query string of the URL can carry a credential.
  def title_for(connection)
    uri = URI.parse(connection.base_url)
    return connection.identifier if uri.host.blank?

    uri.port == uri.default_port ? uri.host : "#{uri.host}:#{uri.port}"
  rescue URI::InvalidURIError
    connection.identifier
  end
end
