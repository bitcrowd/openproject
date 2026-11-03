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
  class DefaultModelsForm < ApplicationForm
    include Redmine::I18n
    include ModelChoiceFields

    # Primer::Forms::Base.new assigns the builder itself and calls this with the
    # remaining keywords, so the builder must not appear in the signature.
    def initialize(chat_provider_id: nil, embedding_provider_id: nil)
      super()
      @chat_provider_id = chat_provider_id
      @embedding_provider_id = embedding_provider_id
    end

    form do |f|
      provider_autocompleter(f,
                             name: :default_chat_provider_id,
                             label: I18n.t("admin.llm_models.defaults.chat_provider"),
                             provider: chat_choice.provider,
                             blank_label: none_label,
                             disabled: read_only?,
                             data: { test_selector: "llm-connection--default-chat-provider" })

      chat_model_autocompleter(f) if chat_choice.provider
      f.hidden(name: :default_chat_model_id, value: "") unless chat_choice.provider

      # Only worth asking for once something embeds.
      if embedding_features?
        provider_autocompleter(f,
                               name: :default_embedding_provider_id,
                               label: I18n.t("admin.llm_models.defaults.embedding_provider"),
                               caption: (embedding_caption unless embedding_choice.provider),
                               provider: embedding_choice.provider,
                               blank_label: none_label,
                               disabled: read_only?,
                               data: { test_selector: "llm-connection--default-embedding-provider" })

        embedding_model_autocompleter(f) if embedding_choice.provider
        f.hidden(name: :default_embedding_model_id, value: "") unless embedding_choice.provider
      end

      f.submit(name: :submit, label: I18n.t(:button_save), scheme: :primary) unless read_only?
    end

    private

    def chat_choice
      @chat_choice ||= ModelChoice.new(model.default_chat_model_id, @chat_provider_id)
    end

    def embedding_choice
      @embedding_choice ||= ModelChoice.new(model.default_embedding_model_id, @embedding_provider_id)
    end

    def none_label = I18n.t("label_none_parentheses")

    def chat_model_autocompleter(form)
      choice_autocompleter(form,
                           name: :default_chat_model_id,
                           label: LlmConnection.human_attribute_name(:default_chat_model_id),
                           caption: I18n.t("admin.llm_models.defaults.chat_caption"),
                           options: chat_model_options.map { |llm_model| [llm_model.name, llm_model] },
                           selected: chat_choice.model,
                           blank_label: none_label,
                           disabled: read_only?,
                           focusDirectly: chat_choice.awaiting_model?)
    end

    def embedding_model_autocompleter(form)
      choice_autocompleter(form,
                           name: :default_embedding_model_id,
                           label: LlmConnection.human_attribute_name(:default_embedding_model_id),
                           caption: embedding_caption,
                           options: embedding_model_options.map { |llm_model| [embedding_option_label(llm_model), llm_model] },
                           selected: embedding_choice.model,
                           blank_label: none_label,
                           disabled: read_only?,
                           focusDirectly: embedding_choice.awaiting_model?)
    end

    def read_only?
      model.configured_from_env?
    end

    # The one already chosen is kept regardless of what the server offers today:
    # dropping it would silently blank the field on the next save.
    def chat_model_options
      (chat_choice.provider.chat_models.to_a + [chat_choice.model]).compact.uniq
    end

    def embedding_features?
      OpenProject::Llm::Features.for_kind(:embedding).any?
    end

    # Only models actually known to embed. Offering one on the grounds that
    # nothing has ruled it out invites a choice whose failure surfaces much
    # later, at index time.
    def embedding_model_options
      (embedding_models + [embedding_choice.model]).compact.uniq
    end

    def embedding_models
      providers = embedding_choice.provider ? [embedding_choice.provider] : InferenceProvider.by_title

      @embedding_models ||= providers.flat_map(&:embedding_models)
    end

    # A stored default the server has never confirmed stays in the list, said
    # so, rather than vanishing from the picker that shows it.
    def embedding_option_label(llm_model)
      return llm_model.name if embedding_models.include?(llm_model)

      I18n.t("admin.llm_models.defaults.embedding_option_unqualified", model: llm_model.name)
    end

    # Says how to make a model eligible when none is, rather than leaving an
    # empty picker with no explanation.
    def embedding_caption
      return I18n.t("admin.llm_models.defaults.embedding_none") if embedding_models.empty?

      link_translate("admin.llm_models.defaults.embedding_caption",
                     links: { docs_url: %i[embeddings_explanation] },
                     external: true)
    end
  end
end
