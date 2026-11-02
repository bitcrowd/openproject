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

require "spec_helper"
require_module_spec_helper
require "contracts/shared/model_contract_shared_context"

RSpec.describe EmbeddingModels::UpdateContract, :check_errors_i18n do
  include_context "ModelContract shared context"

  let(:embedding_model) { create(:embedding_model) }
  let(:contract) { described_class.new(embedding_model, current_user) }

  before { embedding_model.name = "Renamed" }

  it_behaves_like "contract is valid for active admins and invalid for regular users"

  describe "the values that make up the combination" do
    let(:current_user) { build_stubbed(:admin) }

    context "when the model name changes" do
      before { embedding_model.external_id = "another-model" }

      include_examples "contract is invalid", external_id: :error_readonly
    end

    context "when the provider changes" do
      before { embedding_model.inference_provider = create(:inference_provider) }

      include_examples "contract is invalid", inference_provider_id: :error_readonly
    end

    context "when the context length changes" do
      before { embedding_model.context_token_length = 1 }

      include_examples "contract is invalid", context_token_length: :error_readonly
    end

    context "when the dimensions change" do
      before { embedding_model.embedding_vector_dimensions = 1 }

      include_examples "contract is invalid", embedding_vector_dimensions: :error_readonly
    end
  end
end
