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

# :selenium is required, not incidental: axe-core-api drives the browser through
# Selenium's #manage API, so be_axe_clean does not work under cuprite.
RSpec.describe "Semantic index administration",
               :js, :llm_server_helpers, :selenium, :webmock,
               driver: :firefox_de,
               with_flag: { llm_connection: true, semantic_search: true } do
  include Components::Autocompleter::NgSelectAutocompleteHelpers

  include_context "with an embedding model offered"

  shared_let(:admin) { create(:admin) }

  let(:embedding_model) { connection.models.find_by!(external_id: "bge-m3") }

  current_user { admin }

  before do
    Setting.llm_features_enabled = true
    embedding_model.update!(embedding_vector_dimensions: 1024)
  end

  it "fills in what the chosen model knows and keeps what was typed" do
    visit llm_feature_bindings_path
    find_test_selector("llm-semantic-index--new-button").click

    within_test_selector("llm-semantic-index-dialog") do
      fill_in "Display name", with: "Docs"
      fill_in "Dimensions", with: "512"
      select_autocomplete(find("[data-test-selector='llm-semantic-index--model']"), query: "bge", select_text: "bge-m3")

      expect(page).to have_field("Context length", with: "8192")
      expect(page).to have_field("Dimensions", with: "512")
      expect(page).to have_field("Display name", with: "Docs")
      expect(page).to be_axe_clean.within("#llm-semantic-index-dialog")

      find_test_selector("llm-semantic-index--submit").click
    end

    expect(page).to have_test_selector("llm-semantic-index--box", text: "Docs")
    expect(SemanticIndex.sole).to have_attributes(llm_model: embedding_model, context_token_length: 8192,
                                                  embedding_vector_dimensions: 512)
  end
end
