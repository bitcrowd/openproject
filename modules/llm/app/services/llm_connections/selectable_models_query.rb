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

module LlmConnections
  # The models one provider can offer to a feature.
  #
  # A feature is offered the models of its own kind: chat features never see an
  # embedding model, and an embedding feature sees only models known to embed.
  # Offering a model on the grounds that nothing has ruled it out invites a
  # choice whose failure surfaces much later, at index time. A model known to
  # lack a capability the feature requires is left out too, by the same rule
  # Llm::Runtime refuses it with.
  #
  # The one exception is the model a feature is already bound to. It stays
  # listed even once it no longer qualifies, flagged, so that opening the page
  # cannot silently blank a working binding.
  class SelectableModelsQuery
    Option = Data.define(:model, :qualifies)

    def initialize(provider, feature, bound_model: nil)
      @provider = provider
      @feature = feature
      @bound_model = bound_model if bound_model&.inference_provider_id == provider.id
    end

    def call
      offerable_models.map { |model| Option.new(model:, qualifies: qualifying_models.include?(model)) }
    end

    def models_left_out?
      (models_of_kind - qualifying_models).without(bound_model).any?
    end

    private

    attr_reader :provider, :feature, :bound_model

    def offerable_models
      (qualifying_models + [bound_model]).compact.uniq
    end

    def qualifying_models
      @qualifying_models ||= models_of_kind.reject { |model| ruled_out_model_ids.include?(model.external_id) }
    end

    # Withdrawn models are not offered: both lists are built from the active ones.
    def models_of_kind
      @models_of_kind ||= (feature.embedding? ? provider.embedding_models : provider.chat_models).to_a
    end

    def ruled_out_model_ids
      @ruled_out_model_ids ||= provider.capability_verdicts.blocking(feature.requires).distinct.pluck(:model_id)
    end
  end
end
