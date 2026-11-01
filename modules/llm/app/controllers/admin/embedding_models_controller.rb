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
  class EmbeddingModelsController < ApplicationController
    include OpTurbo::ComponentStream

    layout "admin"
    menu_item :llm_connection

    before_action :require_feature
    before_action :require_admin
    before_action :set_connection
    before_action :require_enabled_connection
    before_action :find_llm_model, only: %i[new_dialog create]
    before_action :find_embedding_model, except: %i[new_dialog create]

    def new_dialog
      respond_with_dialog LlmConnections::EmbeddingModels::DialogComponent.new(prefilled_embedding_model,
                                                                               llm_model: @llm_model)
    end

    def edit_dialog
      respond_with_dialog LlmConnections::EmbeddingModels::DialogComponent.new(@embedding_model)
    end

    def create
      result = ::EmbeddingModels::CreateService
                 .new(user: current_user)
                 .call(**embedding_model_params(%i[name model_type context_token_length embedding_vector_dimensions]),
                       external_id: @llm_model.external_id,
                       inference_provider_id: @connection.inference_provider_id)

      respond_to_save(result, notice: t(:notice_successful_create))
    end

    def update
      result = ::EmbeddingModels::UpdateService
                 .new(user: current_user, model: @embedding_model)
                 .call(**embedding_model_params(%i[name]))

      respond_to_save(result, notice: t(:notice_successful_update))
    end

    def deletion_dialog
      respond_with_dialog LlmConnections::EmbeddingModels::DeleteDialogComponent.new(@embedding_model)
    end

    def destroy
      result = ::EmbeddingModels::DeleteService
                 .new(user: current_user, model: @embedding_model)
                 .call

      if result.success?
        flash[:notice] = t(:notice_successful_delete)
      else
        flash[:error] = result.errors.full_messages
      end

      redirect_to llm_models_path, status: :see_other
    end

    private

    def respond_to_save(result, notice:)
      result.on_success do
        flash[:notice] = notice
        redirect_to llm_models_path, status: :see_other
      end

      result.on_failure do
        update_via_turbo_stream(
          component: LlmConnections::EmbeddingModels::FormComponent.new(result.result, llm_model: @llm_model),
          status: :unprocessable_entity
        )
        respond_with_turbo_streams
      end
    end

    def require_feature
      render_404 unless OpenProject::FeatureDecisions.llm_connection_active? &&
                        OpenProject::FeatureDecisions.semantic_search_active?
    end

    def set_connection
      @connection = LlmConnection.active_connection
    end

    def require_enabled_connection
      return if Setting.llm_features_enabled? && @connection.configured?

      flash[:notice] = t("admin.llm_connections.disabled_notice")
      redirect_to llm_connection_path, status: :see_other
    end

    def find_llm_model
      @llm_model = @connection.available_models.find(params.expect(:llm_model_id))
    end

    def find_embedding_model
      @embedding_model = EmbeddingModel.find(params.expect(:id))
    end

    def prefilled_embedding_model
      EmbeddingModel.new(inference_provider: @connection.inference_provider,
                         external_id: @llm_model.external_id,
                         model_type: @llm_model.model_type,
                         context_token_length: @llm_model.context_window,
                         embedding_vector_dimensions: @llm_model.verdict_for(:embeddings)&.dimensions)
    end

    def embedding_model_params(attributes)
      params.expect(embedding_model: attributes).to_h.symbolize_keys
    end
  end
end
