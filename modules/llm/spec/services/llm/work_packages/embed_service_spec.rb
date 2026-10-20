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
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
#
# See COPYRIGHT and LICENSE files for more details.
#++

require "spec_helper"
require_module_spec_helper

RSpec.describe Llm::WorkPackages::EmbedService do
  include_context "with an embedding model offered"

  let(:work_package) { create(:work_package, subject: "Fix bug") }
  let(:semantic_index) do
    create(:semantic_index, model_id: "bge-m3", embedding_vector_dimensions: 3, context_token_length: 512)
  end
  let(:session_double) { instance_double(Llm::Session) }
  let(:embedding_double) { instance_double(RubyLLM::Embedding, vectors: [[1.0, 2.0, 3.0]]) }

  subject(:service) { described_class.new(semantic_index, [work_package]) }

  before do
    allow(Llm::Session).to receive(:for).with(connection).and_return(session_double)
    allow(session_double).to receive(:embed).and_return(embedding_double)
  end

  it "embeds with the parameters of the Semantic Index" do
    allow(Llm::WorkPackages::EmbeddableText).to receive(:for).and_call_original

    service.call

    expect(session_double).to have_received(:embed).with(anything, model: "bge-m3", dimensions: 3)
    expect(Llm::WorkPackages::EmbeddableText).to have_received(:for).with(work_package, context_window: 512)
  end

  it "stores the embedding in the Semantic Index" do
    service.call

    record = WorkPackageEmbedding.find_by!(semantic_index:, work_package:)
    expect(record.embedding).to eq("[1,2,3]")
  end

  it "replaces an earlier embedding of the same work package" do
    service.call
    allow(session_double).to receive(:embed)
      .and_return(instance_double(RubyLLM::Embedding, vectors: [[4.0, 5.0, 6.0]]))

    described_class.new(semantic_index, [work_package]).call

    expect(WorkPackageEmbedding.where(semantic_index:).pluck(:embedding)).to eq(["[4,5,6]"])
  end

  it "leaves the embeddings of other Semantic Indexes alone" do
    other_index = create(:semantic_index)
    create(:work_package_embedding, semantic_index: other_index, work_package:)

    service.call

    expect(WorkPackageEmbedding.where(work_package:).count).to eq(2)
  end
end
