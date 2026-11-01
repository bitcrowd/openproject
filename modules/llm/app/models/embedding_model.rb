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

# A model an administrator stored from the list of the active connection, along
# with the provider serving it.
#
# That list only describes the active provider and is discarded when the server
# changes, so a stored model keeps its own values and survives the switch. The
# same model on another provider is another row.
class EmbeddingModel < ApplicationRecord
  belongs_to :inference_provider, optional: false
  has_many :semantic_indexes, dependent: :restrict_with_error

  attr_accessor :model_type

  scope :for_listing, -> { includes(:inference_provider).order(:name, :id) }

  validates :name, presence: true
  validates :external_id,
            presence: true,
            length: { maximum: LlmModel::MAX_EXTERNAL_ID_LENGTH },
            uniqueness: { scope: %i[inference_provider_id context_token_length embedding_vector_dimensions] }
  validates :context_token_length, numericality: { only_integer: true, greater_than: 0 }
  validates :embedding_vector_dimensions,
            numericality: { only_integer: true, greater_than: 0,
                            less_than_or_equal_to: WorkPackageEmbedding::DIMENSIONS }

  def name_with_provider
    provider_suffix = " @ #{inference_provider.title}"

    name.end_with?(provider_suffix) ? name : "#{name}#{provider_suffix}"
  end
end
