#-- encoding: UTF-8

#-- copyright
# OpenProject is an open source project management software.
# Copyright (C) 2012-2021 the OpenProject GmbH
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
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
# See COPYRIGHT and LICENSE files for more details.
#++

require 'spec_helper'

describe Versions::Scopes::RolledUp, type: :model do
  shared_let(:parent_project) { FactoryBot.create(:project) }
  shared_let(:project) { FactoryBot.create(:project, parent: parent_project) }
  shared_let(:sibling_project) { FactoryBot.create(:project, parent: parent_project) }
  shared_let(:child_project) { FactoryBot.create(:project, parent: project) }
  shared_let(:grand_child_project) { FactoryBot.create(:project, parent: child_project) }
  shared_let(:version) { FactoryBot.create(:version, project: project) }
  shared_let(:child_version) { FactoryBot.create(:version, project: child_project) }
  shared_let(:grand_child_version) { FactoryBot.create(:version, project: grand_child_project) }
  shared_let(:parent_version) { FactoryBot.create(:version, project: parent_project) }
  shared_let(:sibling_version) { FactoryBot.create(:version, project: sibling_project) }

  describe '.rolled_up' do
    it 'includes versions of self and all descendants' do
      expect(project.rolled_up_versions)
        .to match_array [version, child_version, grand_child_version]
    end

    it 'excludes versions from inactive projects' do
      grand_child_project.update(active: false)

      expect(project.rolled_up_versions)
        .to match_array [version, child_version]
    end
  end
end
