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
  class InferenceProvidersController < ApplicationController
    include OpTurbo::ComponentStream

    layout "admin"
    menu_item :llm_connection

    before_action :require_feature
    before_action :require_admin
    before_action :require_features_enabled
    before_action :find_inference_provider, except: %i[new_dialog create]

    def new_dialog
      respond_with_dialog LlmConnections::InferenceProviders::DialogComponent.new(InferenceProvider.new)
    end

    def edit_dialog
      respond_with_dialog LlmConnections::InferenceProviders::DialogComponent.new(@inference_provider)
    end

    def create
      result = ::InferenceProviders::CreateService
                 .new(user: current_user)
                 .call(inference_provider_params(%i[title api_format base_url api_key]))

      result.on_success { activate_and_redirect(result.result, notice: t(:notice_successful_create)) }
      result.on_failure { render_form_with_errors(result.result) }
    end

    def update
      result = ::InferenceProviders::UpdateService
                 .new(user: current_user, model: @inference_provider)
                 .call(inference_provider_params(%i[title api_key]))

      result.on_success do
        refresh_models_for_new_key(result.result)
        redirect_with(notice: t(:notice_successful_update))
      end
      result.on_failure { render_form_with_errors(result.result) }
    end

    def deletion_dialog
      respond_with_dialog LlmConnections::InferenceProviders::DeleteDialogComponent.new(@inference_provider)
    end

    def destroy
      result = ::InferenceProviders::DeleteService
                 .new(user: current_user, model: @inference_provider)
                 .call

      if result.success?
        redirect_with(notice: t(:notice_successful_delete))
      else
        redirect_with(error: result.errors.full_messages)
      end
    end

    def activation_dialog
      respond_with_dialog LlmConnections::InferenceProviders::ActivateDialogComponent.new(
        @inference_provider, current: LlmConnection.active_connection.inference_provider
      )
    end

    def activate
      activate_and_redirect(@inference_provider, notice: t(".success", title: @inference_provider.title))
    end

    def delete_api_key_dialog
      respond_with_dialog LlmConnections::InferenceProviders::DeleteApiKeyDialogComponent.new(@inference_provider)
    end

    def delete_api_key
      @inference_provider.remove_api_key!

      redirect_with(notice: t(".success"))
    end

    private

    def require_feature
      render_404 unless OpenProject::FeatureDecisions.llm_connection_active?
    end

    def require_features_enabled
      redirect_with(notice: t("admin.llm_connections.disabled_notice")) unless Setting.llm_features_enabled?
    end

    def find_inference_provider
      @inference_provider = InferenceProvider.find(params.expect(:id))
    end

    def activate_and_redirect(provider, notice:)
      result = ::InferenceProviders::ActivateService.new(user: current_user, model: provider).call

      if result.failure?
        redirect_with(error: result.errors.full_messages)
      elsif models_fetched?(result)
        redirect_with(notice:)
      else
        redirect_with(warning: t("admin.inference_providers.activate.no_models", title: provider.title))
      end
    end

    # Activating does not check the server, so this is the only sign that it
    # cannot be reached.
    def models_fetched?(activation)
      activation.dependent_results.none?(&:failure?) && activation.result.reload.models.any?
    end

    # Synchronous, as the page the redirect leads to shows what the catalogue
    # holds. The contract has proven the server accepts the key, and a failed
    # refresh is logged by the service.
    def refresh_models_for_new_key(provider)
      return unless provider.saved_change_to_api_key? && provider.active?

      ::LlmConnections::SyncModelsService.new(LlmConnection.active_connection).call
    end

    def render_form_with_errors(provider)
      update_via_turbo_stream(
        component: LlmConnections::InferenceProviders::FormComponent.new(provider),
        status: :unprocessable_entity
      )
      respond_with_turbo_streams
    end

    def redirect_with(**flashes)
      flashes.each { |type, message| flash[type] = message }

      redirect_to llm_connection_path, status: :see_other
    end

    # A blank API key means "keep the stored one": the form never renders the
    # saved value, so submitting it unchanged posts an empty string.
    def inference_provider_params(attributes)
      permitted = params.expect(inference_provider: attributes)
      permitted.delete(:api_key) if permitted[:api_key].blank?
      permitted
    end
  end
end
