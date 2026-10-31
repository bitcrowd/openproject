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

module InferenceProviders
  # Points the active connection at a provider and refreshes the catalogue.
  #
  # A failed refresh does not undo the switch. It is added to the result's
  # dependent_results, without touching its success, so the caller can report it.
  class ActivateService < ::BaseServices::BaseCallable
    attr_reader :user, :model

    def initialize(user:, model:)
      super()
      @user = user
      @model = model
    end

    protected

    def perform
      activation = point_active_connection_at_provider
      return activation if activation.failure?

      connection = activation.result
      if ::LlmConnections::UpdateService.models_to_refresh?(connection)
        activation.dependent_results << ::LlmConnections::SyncModelsService.new(connection).call
      end

      activation
    end

    private

    def point_active_connection_at_provider
      ::LlmConnections::UpdateService
        .new(user:,
             model: LlmConnection.active_connection,
             contract_class: ::LlmConnections::ActivateProviderContract)
        .call(inference_provider_id: model.id)
    end
  end
end
