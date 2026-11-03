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

# Which model a registered feature uses.
#
# One row per feature, not per binding: rows are reconciled against the registry
# and are never destroyed when a feature deregisters, so flipping a feature flag
# does not lose the administrator's choice.
class LlmFeatureBinding < ApplicationRecord
  belongs_to :llm_connection, optional: false
  belongs_to :llm_model, optional: true
  belongs_to :semantic_index, optional: true

  validates :feature_key, presence: true, uniqueness: { scope: :llm_connection_id }
  validate :feature_registered
  validate :model_offered, if: :llm_model_id_changed?
  validate :semantic_index_only_for_embedding, if: :semantic_index_id_changed?

  def feature
    OpenProject::Llm::Features[feature_key]
  rescue OpenProject::Llm::UnknownFeature
    nil
  end

  # NULL means "use the connection default for this kind of model".
  def resolved_model
    llm_model || default_model
  end

  # Derived, never stored. A status column would be a cache with no invalidation
  # trigger, and would be stale exactly when it matters -- right after the remote
  # catalogue changed.
  def dangling?
    resolved = resolved_model
    resolved.present? && !resolved.active?
  end

  private

  def default_model
    return if feature.nil?

    llm_connection.default_model_for(feature)
  end

  def feature_registered
    return if feature.present?

    errors.add(:feature_key, :not_registered)
  end

  # Only checked when it changes, so a catalogue that shrinks underneath a stored
  # binding does not block unrelated saves; #dangling? reports that state.
  def model_offered
    return if llm_model_id.blank?
    return if LlmModel.active.exists?(id: llm_model_id)

    errors.add(:llm_model_id, :not_available)
  end

  def semantic_index_only_for_embedding
    return if semantic_index.nil?
    return if feature&.embedding?

    errors.add(:semantic_index, :not_for_chat_feature)
  end
end
