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
  class LlmHealthStatusController < ApplicationController
    layout "admin"

    before_action :require_feature
    before_action :require_admin
    before_action :require_features_enabled
    before_action :find_inference_provider

    menu_item :llm_connection

    helper_method :tally_counts

    def show
      @report = @inference_provider.latest_health_report

      respond_to do |format|
        format.html
        format.text do
          return head :not_found if @report.nil?

          timestamp = @report.created_at.iso8601
          send_data text_report(timestamp),
                    filename: "llm_connection_health_report_#{timestamp}.txt",
                    type: "text/plain",
                    disposition: :attachment
        end
      end
    end

    # A full run, including the billed completion: an administrator clicking
    # "Run checks" is asking whether the provider actually works.
    def create
      report = run_checks
      flash[:notice] = t(".success", **tally_counts(report))
      redirect_to inference_provider_health_status_report_path(@inference_provider), status: :see_other
    end

    private

    # Downloaded and pasted into support tickets, so it must not contain the API
    # key or the custom headers -- a gateway header routinely carries a second
    # credential.
    def text_report(timestamp)
      {
        inference_provider: @inference_provider.title,
        configuration: @inference_provider.non_confidential_configuration,
        ran_at: timestamp,
        results: @report ? @report.results.map(&:to_h) : []
      }.to_yaml(stringify_names: true)
    end

    def tally_counts(report)
      tally = report.tally

      { passed: tally[:success].to_i, warnings: tally[:warning].to_i, failures: tally[:failure].to_i }
    end

    def run_checks
      @inference_provider.deep_health_check = true
      report = Llm::Validators::ConnectionValidator.new(@inference_provider).call
      report.save!
      report
    end

    def find_inference_provider
      @inference_provider = InferenceProvider.find(params.expect(:inference_provider_id))
    end

    def require_features_enabled
      return if Setting.llm_features_enabled?

      flash[:notice] = t("admin.llm_connections.disabled_notice")
      redirect_to llm_connection_path, status: :see_other
    end

    # The flag gates the endpoints, not only the menu entry: an unfinished page
    # must not accept writes just because somebody knows the URL.
    def require_feature
      render_404 unless OpenProject::FeatureDecisions.llm_connection_active?
    end
  end
end
