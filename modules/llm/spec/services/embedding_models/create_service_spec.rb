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

RSpec.describe EmbeddingModels::CreateService do
  subject(:result) { described_class.new(user: create(:admin)).call(params) }

  let(:provider) { create(:inference_provider, title: "Ollama") }
  let(:params) do
    { inference_provider_id: provider.id, external_id: "bge-m3", name:,
      context_token_length: 8192, embedding_vector_dimensions: 1024 }
  end
  let(:name) { "Our embeddings" }

  it "stores the model with its provider" do
    expect(result).to be_success

    expect(result.result.reload)
      .to have_attributes(name: "Our embeddings", external_id: "bge-m3", inference_provider: provider,
                          context_token_length: 8192, embedding_vector_dimensions: 1024)
  end

  context "without a name" do
    let(:name) { "" }

    it "names it after the model and the provider" do
      expect(result).to be_success

      expect(result.result.reload.name).to eq("bge-m3 @ Ollama")
    end
  end

  context "with a user who is no administrator" do
    subject(:result) { described_class.new(user: create(:user)).call(params) }

    it "stores nothing" do
      expect(result).to be_failure

      expect(EmbeddingModel.count).to eq(0)
    end
  end
end
