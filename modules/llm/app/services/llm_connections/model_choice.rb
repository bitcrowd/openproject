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
  # What a provider select and the model select it fills show. The provider is
  # not stored: it follows from the model, until an administrator picks another
  # one and the model has to be chosen anew.
  class ModelChoice
    attr_reader :provider, :model

    # +picked_provider_id+ is nil until the form has been posted, and blank once
    # no provider was picked.
    def initialize(model_id, picked_provider_id = nil)
      current = LlmModel.find_by(id: model_id)

      @picked = picked_provider_id.present?
      @provider = picked_provider_id.nil? ? current&.inference_provider : InferenceProvider.find_by(id: picked_provider_id)
      @model = current if current && current.inference_provider_id == @provider&.id
    end

    def awaiting_model? = @picked && provider.present? && model.nil?
  end
end
