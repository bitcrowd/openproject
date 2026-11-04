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

RSpec.describe LlmConnections::ModelChoice do
  subject(:choice) { described_class.new(model_id, picked_provider_id) }

  let(:provider) { create(:inference_provider) }
  let(:llm_model) { create(:llm_model, inference_provider: provider) }
  let(:model_id) { llm_model.id }
  let(:picked_provider_id) { nil }

  context "when nothing has been posted yet" do
    it "follows the model" do
      expect(choice).to have_attributes(provider:, model: llm_model, awaiting_model?: false)
    end

    context "without a model" do
      let(:model_id) { nil }

      it "has no provider either" do
        expect(choice).to have_attributes(provider: nil, model: nil, awaiting_model?: false)
      end
    end
  end

  context "with the provider of the model picked" do
    let(:picked_provider_id) { provider.id.to_s }

    it "keeps the model" do
      expect(choice).to have_attributes(provider:, model: llm_model, awaiting_model?: false)
    end
  end

  context "with another provider picked" do
    let(:other_provider) { create(:inference_provider) }
    let(:picked_provider_id) { other_provider.id.to_s }

    it "forgets the model and waits for one" do
      expect(choice).to have_attributes(provider: other_provider, model: nil, awaiting_model?: true)
    end
  end

  context "with no provider picked" do
    let(:picked_provider_id) { "" }

    it "forgets the model" do
      expect(choice).to have_attributes(provider: nil, model: nil, awaiting_model?: false)
    end
  end

  context "with a provider that is gone" do
    let(:picked_provider_id) { "0" }

    it "reads as no provider" do
      expect(choice).to have_attributes(provider: nil, model: nil, awaiting_model?: false)
    end
  end
end
