//-- copyright
// OpenProject is an open source project management software.
// Copyright (C) the OpenProject GmbH
//
// This program is free software; you can redistribute it and/or
// modify it under the terms of the GNU General Public License version 3.
//
// OpenProject is a fork of ChiliProject, which is a fork of Redmine. The copyright follows:
// Copyright (C) 2006-2013 Jean-Philippe Lang
// Copyright (C) 2010-2013 the ChiliProject Team
//
// This program is free software; you can redistribute it and/or
// modify it under the terms of the GNU General Public License
// as published by the Free Software Foundation; either version 2
// of the License, or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.
//
// See COPYRIGHT and LICENSE files for more details.
//++

import { Controller } from '@hotwired/stimulus';

interface ModelDefaults {
  contextLength:number|null;
  dimensions:number|null;
}

export default class extends Controller {
  static targets = ['contextLength', 'dimensions'];
  static values = { defaults: Object };

  declare readonly contextLengthTarget:HTMLInputElement;
  declare readonly dimensionsTarget:HTMLInputElement;
  declare readonly defaultsValue:Record<string, ModelDefaults>;

  prefill(event:Event):void {
    const defaults = this.defaultsValue[(event.target as HTMLSelectElement).value];

    this.fill(this.contextLengthTarget, defaults?.contextLength);
    this.fill(this.dimensionsTarget, defaults?.dimensions);
  }

  // A value the administrator typed stays. One that came from the previously
  // selected model follows the selection.
  private fill(input:HTMLInputElement, value:number|null|undefined):void {
    if (input.value !== '' && input.value !== input.dataset.prefilled) {
      return;
    }

    input.value = value?.toString() ?? '';
    input.dataset.prefilled = input.value;
  }
}
