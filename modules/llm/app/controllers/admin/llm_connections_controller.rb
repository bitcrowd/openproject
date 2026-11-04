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
    include OpTurbo::ComponentStream

    layout "admin"
    menu_item :llm_connection

    before_action :require_feature
    before_action :require_admin
    before_action :set_connection

    def show
      @inference_provider = InferenceProvider.new if InferenceProvider.none?
      @features_enabled = Setting.llm_features_enabled?
    end

    def update
      save_switch(params.expect(llm_connection: %i[llm_features_enabled])[:llm_features_enabled])
    end

    # While no provider exists, switching the features on and naming the first
    # server are one save, and a server that does not answer saves neither.
    def setup
      return save_switch("0") unless features_requested?

      result = ::InferenceProviders::CreateService
                 .new(user: current_user)
                 .call(inference_provider_params)

      result.on_success { save_switch("1") }
      result.on_failure { render_form_with_errors(result.result) }
    end

    private

    def set_connection
      @connection = LlmConnection.current
    end

    # The flag gates the endpoints, not only the menu entry: an unfinished page
    # must not accept writes just because somebody knows the URL.
    def require_feature
      render_404 unless OpenProject::FeatureDecisions.llm_connection_active?
    end

    def features_requested?
      return Setting.llm_features_enabled? unless Setting.llm_features_enabled_writable?

      ActiveModel::Type::Boolean.new.cast(params[:llm_features_enabled])
    end

    def save_switch(enabled)
      result = update_switch(enabled)
      # Switching the AI features on or off decides whether the scheduled health
      # check has anything to do.
      Llm::HealthCheckJob.toggle_cron_job

      if result.success?
        flash[:notice] = t("admin.llm_connections.update.#{Setting.llm_features_enabled? ? :success : :disabled}")
      else
        flash[:error] = result.message
      end

      redirect_to llm_connection_path, status: :see_other
    end

    def update_switch(enabled)
      return ServiceResult.success unless Setting.llm_features_enabled_writable?

      ::Settings::UpdateService.new(user: current_user).call(llm_features_enabled: enabled)
    end

    def render_form_with_errors(inference_provider)
      @inference_provider = inference_provider
      @features_enabled = true

      update_via_turbo_stream(
        component: ::LlmConnections::FormComponent.new(@connection, inference_provider:, features_enabled: true)
      )
      respond_with_turbo_streams do |format|
        format.html { render :show }
      end
    end

    # A blank API key means "no key": the form never renders a saved value.
    def inference_provider_params
      permitted = params.expect(inference_provider: %i[title api_format base_url api_key])
      permitted.delete(:api_key) if permitted[:api_key].blank?
      permitted.to_h.symbolize_keys
    end
  end
end
