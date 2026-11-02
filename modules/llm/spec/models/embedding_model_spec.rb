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

RSpec.describe EmbeddingModel do
  describe "validations" do
    subject(:embedding_model) { build(:embedding_model) }

    it "is valid with a provider, a model name and both parameters" do
      expect(embedding_model).to be_valid
    end

    it "needs a provider" do
      embedding_model.inference_provider = nil

      expect(embedding_model).not_to be_valid
      expect(embedding_model.errors).to be_of_kind(:inference_provider, :blank)
    end

    it "limits the model name to what a model row can hold" do
      embedding_model.external_id = "x" * (LlmModel::MAX_EXTERNAL_ID_LENGTH + 1)

      expect(embedding_model).not_to be_valid
      expect(embedding_model.errors).to be_of_kind(:external_id, :too_long)
    end

    %i[context_token_length embedding_vector_dimensions].product([nil, 0, -1, 1.5]).each do |parameter, value|
      it "refuses #{value.inspect} for #{parameter}" do
        embedding_model.public_send(:"#{parameter}=", value)

        expect(embedding_model).not_to be_valid
        expect(embedding_model.errors).to include(parameter)
      end
    end

    it "limits the dimensions to what an embedding column can hold" do
      embedding_model.embedding_vector_dimensions = WorkPackageEmbedding::DIMENSIONS + 1

      expect(embedding_model).not_to be_valid
      expect(embedding_model.errors).to be_of_kind(:embedding_vector_dimensions, :less_than_or_equal_to)
    end
  end

  describe "what makes it the same embedding model" do
    let(:provider) { create(:inference_provider) }
    let(:values) do
      { inference_provider: provider, external_id: "bge-m3", context_token_length: 8192, embedding_vector_dimensions: 1024 }
    end

    before { create(:embedding_model, **values) }

    it "refuses the same model and parameters on the same provider" do
      duplicate = build(:embedding_model, **values)

      expect(duplicate).not_to be_valid
      expect(duplicate.errors).to be_of_kind(:external_id, :taken)
    end

    it "does not look at the name" do
      expect(build(:embedding_model, **values, name: "Another name")).not_to be_valid
    end

    it "accepts the same model and parameters on another provider" do
      expect(build(:embedding_model, **values, inference_provider: create(:inference_provider))).to be_valid
    end

    it "accepts other parameters on the same provider" do
      expect(build(:embedding_model, **values, context_token_length: 512)).to be_valid
      expect(build(:embedding_model, **values, embedding_vector_dimensions: 512)).to be_valid
    end
  end

  describe "#name_with_provider" do
    let(:provider) { build(:inference_provider, title: "Ollama") }

    it "adds the provider to a name without it" do
      expect(build(:embedding_model, inference_provider: provider, name: "Large").name_with_provider)
        .to eq("Large @ Ollama")
    end

    it "does not repeat the provider of a default name" do
      expect(build(:embedding_model, inference_provider: provider, name: "bge-m3 @ Ollama").name_with_provider)
        .to eq("bge-m3 @ Ollama")
    end
  end

  describe "deleting its provider" do
    let(:embedding_model) { create(:embedding_model) }

    it "is refused while the model is stored" do
      provider = embedding_model.inference_provider

      expect(provider.destroy).to be(false)
      expect(described_class.exists?(embedding_model.id)).to be(true)
    end
  end
end
