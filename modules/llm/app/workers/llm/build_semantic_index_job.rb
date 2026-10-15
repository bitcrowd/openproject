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
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
# See COPYRIGHT and LICENSE files for more details.
#++

module Llm
  # Simulates indexing until the real pipeline writes into a Semantic Index.
  class BuildSemanticIndexJob < ApplicationJob
    SIMULATED_DURATION = 5.seconds
    SIMULATED_FAILURE_RATE = 0.3
    SIMULATED_ERROR_MESSAGE = "Some Error"

    queue_with_priority :low

    def self.enqueue_for(semantic_index)
      set(wait: SIMULATED_DURATION).perform_later(semantic_index.id)
    end

    def perform(semantic_index_id)
      semantic_index = SemanticIndex.find_by(id: semantic_index_id)
      return unless semantic_index&.indexing?

      if Random.rand < SIMULATED_FAILURE_RATE
        semantic_index.fail_indexing!(SIMULATED_ERROR_MESSAGE)
      else
        semantic_index.finish_indexing!
      end
    end
  end
end
