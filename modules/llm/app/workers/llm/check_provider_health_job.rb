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

module Llm
  # The full check of one provider, billed completion included: what an
  # administrator asks for with "Run health check", so that the provider list
  # shows how it went.
  class CheckProviderHealthJob < ApplicationJob
    include GoodJob::ActiveJobExtensions::Concurrency

    # The default key is the class name, which would swallow another provider's job.
    good_job_control_concurrency_with(enqueue_limit: 1, perform_limit: 1,
                                      key: -> { "#{self.class.name}-#{arguments.first}" })

    def perform(inference_provider_id)
      provider = InferenceProvider.find_by(id: inference_provider_id)
      return if provider.nil?

      provider.deep_health_check = true
      Llm::Validators::ConnectionValidator.new(provider).call.save!
    end
  end
end
