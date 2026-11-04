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

RSpec.describe InferenceProviders::DeleteContract, :check_errors_i18n do
  include_context "ModelContract shared context"

  let(:provider) { create(:inference_provider) }
  let(:contract) { described_class.new(provider, current_user) }

  it_behaves_like "contract is valid for active admins and invalid for regular users"

  context "when one of its models is in use" do
    let(:current_user) { build_stubbed(:admin) }

    before { create(:semantic_index, llm_model: create(:llm_model, inference_provider: provider)) }

    include_examples "contract is invalid", base: :in_use
  end

  context "when the models of another provider are in use" do
    let(:current_user) { build_stubbed(:admin) }

    before { create(:llm_feature_binding, llm_model: create(:llm_model)) }

    include_examples "contract is valid"
  end
end
