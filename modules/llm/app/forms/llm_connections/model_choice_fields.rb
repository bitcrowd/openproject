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
  # The two elements that choose a model. Picking a provider asks the server for
  # the form again, with that provider's models in the second.
  module ModelChoiceFields
    REFRESH_ON_CHANGE = "change->refresh-on-form-changes#triggerTurboStream"

    private

    def provider_autocompleter(form, provider:, **)
      choice_autocompleter(form,
                           options: InferenceProvider.by_title.map { |item| [item.title, item] },
                           selected: provider,
                           hiddenFieldAction: REFRESH_ON_CHANGE,
                           focusDirectly: false,
                           **)
    end

    # +options+ are pairs of a label and the record it stands for.
    def choice_autocompleter(form, name:, label:, options:, selected:, blank_label: nil, caption: nil, required: false, **inputs)
      form.autocompleter(
        name:,
        label:,
        caption:,
        required:,
        autocomplete_options: { decorated: true, inputValue: selected&.id, placeholder: blank_label, **inputs }
      ) do |list|
        list.option(label: blank_label, value: "", selected: selected.nil?) if blank_label

        options.each do |option_label, record|
          list.option(label: option_label, value: record.id, selected: selected == record)
        end
      end
    end
  end
end
