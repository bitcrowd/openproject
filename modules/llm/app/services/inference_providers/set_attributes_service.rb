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
  class SetAttributesService < ::BaseServices::SetAttributes
    private

    def set_attributes(params)
      super

      model.title = unique_title(model.host_and_port) if model.title.blank?
    end

    # A second key on the same server has the same host and port, and a title
    # nobody typed is no reason to refuse the save.
    def unique_title(title)
      return title if title.nil? || InferenceProvider.where.not(id: model.id).where(title:).none?

      (2..).lazy.map { |number| "#{title} (#{number})" }
           .find { |candidate| InferenceProvider.where.not(id: model.id).where(title: candidate).none? }
    end
  end
end
