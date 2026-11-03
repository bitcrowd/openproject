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

class MoveLlmServerSettingsAndModelListsToInferenceProviders < ActiveRecord::Migration[8.1]
  VERDICT_CONNECTION_INDEX = "index_llm_capability_verdicts_on_connection_model_capability"
  VERDICT_PROVIDER_INDEX = "index_llm_capability_verdicts_on_provider_model_capability"
  LIST_TABLES = %i[llm_models llm_capability_verdicts].freeze

  class MigrationConnection < ApplicationRecord
    self.table_name = "llm_connections"
  end

  class MigrationProvider < ApplicationRecord
    self.table_name = "inference_providers"
  end

  def up
    create_inference_providers
    add_reference :llm_connections, :inference_provider
    LIST_TABLES.each { |table| add_reference table, :inference_provider, foreign_key: true, index: false }

    MigrationConnection.reset_column_information
    MigrationProvider.reset_column_information
    MigrationConnection.order(:id).find_each { |connection| move_settings_to_provider(connection) }

    move_lists_to_providers
    move_health_reports_to_providers
    collapse_connections

    remove_columns :llm_connections, :inference_provider_id, :base_url, :api_key, :api_format, :custom_headers, :options,
                   :last_synced_at, :last_connected_at, :connection_fingerprint, :active
  end

  def down
    refuse_when_another_provider_is_in_use
    restore_connection_columns

    MigrationConnection.reset_column_information
    MigrationProvider.reset_column_information
    connection = restore_connection

    restore_lists(connection)
    restore_health_reports(connection)

    change_column_null :llm_connections, :base_url, false
    add_index :llm_connections, :active, unique: true, where: "active"
    drop_table :inference_providers
  end

  private

  def create_inference_providers
    create_table :inference_providers do |t|
      t.string :title, null: false, index: { unique: true }
      t.string :base_url, null: false
      # Nullable: an unauthenticated self-hosted server needs no key.
      t.string :api_key
      # Which dialect the server speaks. Only a subset is implemented; the column
      # exists so that adding a format is a new adapter rather than a migration.
      t.string :api_format, null: false, default: "openai"
      # Provider-specific headers sent with every request, e.g. Azure's
      # api-version or a gateway's own key header.
      t.jsonb :custom_headers, null: false, default: {}
      t.jsonb :options, null: false, default: {}
      t.datetime :last_synced_at
      t.datetime :last_connected_at

      t.timestamps null: false
    end
  end

  def move_settings_to_provider(connection)
    provider = MigrationProvider.create!(
      title: unique_title(connection),
      **connection.slice(:base_url, :api_key, :api_format, :custom_headers, :options, :last_synced_at, :last_connected_at)
    )

    connection.update_columns(inference_provider_id: provider.id)
  end

  def unique_title(connection)
    title = title_for(connection)
    taken = MigrationProvider.pluck(:title)
    return title if taken.exclude?(title)

    (2..).lazy.map { |number| "#{title} (#{number})" }.find { |candidate| taken.exclude?(candidate) }
  end

  # Host and port only: the userinfo or query string of the URL can carry a credential.
  def title_for(connection)
    uri = URI.parse(connection.base_url)
    return connection.identifier if uri.host.blank?

    uri.port == uri.default_port ? uri.host : "#{uri.host}:#{uri.port}"
  rescue URI::InvalidURIError
    connection.identifier
  end

  def move_lists_to_providers
    LIST_TABLES.each do |table|
      execute <<~SQL.squish
        UPDATE #{table}
        SET inference_provider_id = llm_connections.inference_provider_id
        FROM llm_connections
        WHERE #{table}.llm_connection_id = llm_connections.id
      SQL

      change_column_null table, :inference_provider_id, false
    end

    remove_index :llm_capability_verdicts, name: VERDICT_CONNECTION_INDEX
    remove_index :llm_models, column: %i[llm_connection_id external_id]
    LIST_TABLES.each { |table| remove_reference table, :llm_connection, foreign_key: true }

    add_index :llm_models, %i[inference_provider_id external_id], unique: true
    add_index :llm_capability_verdicts, %i[inference_provider_id model_id capability],
              unique: true, name: VERDICT_PROVIDER_INDEX
  end

  def move_health_reports_to_providers
    execute <<~SQL.squish
      UPDATE health_reports
      SET subject_type = 'InferenceProvider', subject_id = llm_connections.inference_provider_id
      FROM llm_connections
      WHERE health_reports.subject_type = 'LlmConnection'
        AND health_reports.subject_id = llm_connections.id
    SQL
  end

  # The defaults and feature bindings of the connection features resolved against
  # are the ones that were in effect.
  def collapse_connections
    kept = MigrationConnection.order(active: :desc, id: :asc).pick(:id)
    return if kept.nil?

    execute "DELETE FROM llm_feature_bindings WHERE llm_connection_id <> #{kept}"
    execute "DELETE FROM llm_connections WHERE id <> #{kept}"
  end

  # The previous schema holds a single server, and its strings could only name
  # models of that server.
  def refuse_when_another_provider_is_in_use
    first_provider_id = select_value("SELECT MIN(id) FROM inference_providers")
    return if first_provider_id.nil?

    in_use = select_value(<<~SQL.squish)
      SELECT COUNT(*) FROM llm_models
      WHERE inference_provider_id <> #{first_provider_id}
        AND (id IN (SELECT llm_model_id FROM semantic_indexes)
             OR id IN (SELECT llm_model_id FROM llm_feature_bindings WHERE llm_model_id IS NOT NULL))
    SQL
    return if in_use.to_i.zero?

    raise ActiveRecord::IrreversibleMigration,
          "Semantic indexes or feature bindings use models of a provider other than the first one."
  end

  def restore_connection_columns
    change_table :llm_connections, bulk: true do |t|
      t.boolean :active, null: false, default: true
      t.string :base_url
      t.string :api_key
      t.string :api_format, null: false, default: "openai"
      t.jsonb :custom_headers, null: false, default: {}
      t.jsonb :options, null: false, default: {}
      t.datetime :last_synced_at
      t.string :connection_fingerprint
      t.datetime :last_connected_at
    end
  end

  def restore_connection
    provider = MigrationProvider.order(:id).first
    connection = MigrationConnection.first

    if provider.nil?
      execute "DELETE FROM llm_feature_bindings"
      execute "DELETE FROM llm_connections"
      return
    end

    connection ||= MigrationConnection.new(identifier: "default")
    connection.update!(
      provider.slice(:base_url, :api_key, :api_format, :custom_headers, :options, :last_synced_at, :last_connected_at)
    )
    connection
  end

  def restore_lists(connection)
    first_provider_id = connection && select_value("SELECT MIN(id) FROM inference_providers")

    LIST_TABLES.each do |table|
      add_reference table, :llm_connection, foreign_key: true
      execute "DELETE FROM #{table} WHERE inference_provider_id <> #{first_provider_id}" if first_provider_id
      execute "UPDATE #{table} SET llm_connection_id = #{connection.id}" if connection
      change_column_null table, :llm_connection_id, false
    end

    remove_index :llm_capability_verdicts, name: VERDICT_PROVIDER_INDEX
    remove_index :llm_models, column: %i[inference_provider_id external_id]
    LIST_TABLES.each { |table| remove_reference table, :inference_provider, foreign_key: true, index: false }

    add_index :llm_models, %i[llm_connection_id external_id], unique: true
    add_index :llm_capability_verdicts, %i[llm_connection_id model_id capability],
              unique: true, name: VERDICT_CONNECTION_INDEX
  end

  def restore_health_reports(connection)
    first_provider_id = select_value("SELECT MIN(id) FROM inference_providers")

    if connection
      execute <<~SQL.squish
        UPDATE health_reports
        SET subject_type = 'LlmConnection', subject_id = #{connection.id}
        WHERE subject_type = 'InferenceProvider' AND subject_id = #{first_provider_id}
      SQL
    end

    execute "DELETE FROM health_reports WHERE subject_type = 'InferenceProvider'"
  end
end
