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
  module InferenceProviders
    class BoxComponent < ApplicationComponent
      include OpPrimer::ComponentHelpers
      include OpTurbo::Streamable

      POLL_INTERVAL_MS = 2000

      options :inference_providers

      def rows = inference_providers

      def activity
        @activity ||= Llm::ProviderActivity.new(inference_providers)
      end

      def wrapper_data_attrs
        data = { test_selector: "llm-inference-provider--box" }
        return { data: } unless activity.any?

        data.merge!(
          controller: "poll-for-changes",
          poll_for_changes_url_value: status_inference_providers_path,
          poll_for_changes_interval_value: POLL_INTERVAL_MS,
          poll_for_changes_reference_value: activity.reference
        )
        { data: }
      end
    end
  end
end
