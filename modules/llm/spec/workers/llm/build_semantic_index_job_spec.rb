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

RSpec.describe Llm::BuildSemanticIndexJob do
  include_context "with an embedding model offered"

  let(:semantic_index) { create(:semantic_index, state: "indexing") }

  it "makes the Semantic Index ready when the simulation succeeds" do
    allow(Random).to receive(:rand).and_return(described_class::SIMULATED_FAILURE_RATE)

    described_class.perform_now(semantic_index.id)

    expect(semantic_index.reload).to be_ready
  end

  it "fails the Semantic Index with an error message when the simulation fails" do
    allow(Random).to receive(:rand).and_return(0.0)

    described_class.perform_now(semantic_index.id)

    expect(semantic_index.reload).to have_attributes(state: "failed", error_message: "Some Error")
  end

  it "leaves a Semantic Index alone that is no longer indexing" do
    semantic_index.update!(state: "not_indexed")

    described_class.perform_now(semantic_index.id)

    expect(semantic_index.reload).to be_not_indexed
  end

  it "ignores a deleted Semantic Index" do
    expect { described_class.perform_now(0) }.not_to raise_error
  end
end
