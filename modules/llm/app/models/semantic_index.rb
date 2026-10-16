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
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
#
# See COPYRIGHT and LICENSE files for more details.
#++

class SemanticIndex < ApplicationRecord
  class InvalidTransitionError < StandardError; end

  INDEXABLE_STATES = %w[not_indexed failed ready].freeze
  PARAMETERS = %w[model_id embedding_vector_dimensions context_token_length].freeze

  has_many :llm_feature_bindings, dependent: :restrict_with_error

  enum :state, {
    not_indexed: "not_indexed",
    indexing: "indexing",
    ready: "ready",
    failed: "failed"
  }

  validates :title, presence: true
  validates :model_id, presence: true, length: { maximum: LlmModel::MAX_EXTERNAL_ID_LENGTH }
  validates :embedding_vector_dimensions, :context_token_length,
            numericality: { only_integer: true, greater_than: 0 }

  validate :model_offered, if: -> { model_id.present? && model_id_changed? }

  def self.semantic_search_binding
    LlmConnection.active_connection.feature_bindings.find_or_initialize_by(feature_key: "semantic_search")
  end

  def active? = llm_feature_bindings.exists?

  def indexable? = INDEXABLE_STATES.include?(state)

  def parameters_locked? = !not_indexed?

  def start_indexing!
    with_lock do
      raise InvalidTransitionError, "cannot start indexing from #{state}" unless indexable?

      update!(state: :indexing, error_message: nil)
    end
  end

  def finish_indexing!
    transition_from_indexing!(state: :ready)
  end

  def fail_indexing!(error_message)
    transition_from_indexing!(state: :failed, error_message:)
  end

  private

  def transition_from_indexing!(**attributes)
    with_lock do
      raise InvalidTransitionError, "cannot finish indexing from #{state}" unless indexing?

      update!(**attributes)
    end
  end

  def model_offered
    return if LlmConnection.active_connection.embedding_model_ids.include?(model_id)

    errors.add(:model_id, :not_offered)
  end
end
