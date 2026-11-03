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
  class ConnectionForm < ApplicationForm
    form do |f|
      f.check_box(
        name: :llm_features_enabled,
        label: LlmConnection.human_attribute_name(:llm_features_enabled),
        caption: features_caption,
        disabled: locked?
      )

      f.submit(name: :submit, label: I18n.t(:button_save), scheme: :primary) unless locked?
    end

    private

    def locked?
      !Setting.llm_features_enabled_writable?
    end

    def features_caption
      return I18n.t("admin.llm_connections.form.llm_features_enabled_caption_env") if locked?

      I18n.t("admin.llm_connections.form.llm_features_enabled_caption")
    end
  end
end
