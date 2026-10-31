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

module Admin
  class LlmConnectionsController < ApplicationController
    layout "admin"
    menu_item :llm_connection

    before_action :require_feature
    before_action :require_admin
    before_action :set_connection

    def show; end

    def update
      result = ::Settings::UpdateService
                 .new(user: current_user)
                 .call(**llm_connection_params)
      # Switching the AI features on or off decides whether the scheduled health
      # check has anything to do.
      Llm::HealthCheckJob.toggle_cron_job

      result.on_success { redirect_after_save }
      result.on_failure do
        flash[:error] = result.message
        redirect_to llm_connection_path, status: :see_other
      end
    end

    private

    def set_connection
      @connection = LlmConnection.active_connection
    end

    # The flag gates the endpoints, not only the menu entry: an unfinished page
    # must not accept writes just because somebody knows the URL.
    def require_feature
      render_404 unless OpenProject::FeatureDecisions.llm_connection_active?
    end

    # A connection can be perfectly usable without offering a model list, so the
    # save succeeds either way; the administrator is told what to do next rather
    # than being left with an empty table and no explanation.
    def redirect_after_save
      return redirect_with_notice(t(".disabled")) unless Setting.llm_features_enabled?

      if @connection.configured? && @connection.models.none?
        flash[:warning] = t(".no_models")
      else
        flash[:notice] = t(".success")
      end

      redirect_to llm_connection_path, status: :see_other
    end

    def redirect_with_notice(message)
      flash[:notice] = message
      redirect_to llm_connection_path, status: :see_other
    end

    def llm_connection_params
      params.expect(llm_connection: %i[llm_features_enabled]).to_h.symbolize_keys
    end
  end
end
