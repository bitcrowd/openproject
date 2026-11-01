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

import SemanticIndexFormController from './semantic-index-form.controller';
import { setupStimulusTest, type StimulusTestContext } from 'core-stimulus/test-helpers';

describe('SemanticIndexFormController', () => {
  let ctx:StimulusTestContext;
  let model:HTMLSelectElement;
  let contextLength:HTMLInputElement;
  let dimensions:HTMLInputElement;

  const defaults = {
    1: { contextLength: 8192, dimensions: 1024 },
    2: { contextLength: 2048, dimensions: 768 },
    3: { contextLength: null, dimensions: null },
  };

  const select = (value:string) => {
    model.value = value;
    model.dispatchEvent(new Event('change', { bubbles: true }));
  };

  beforeEach(async () => {
    ctx = await setupStimulusTest({
      controllers: { 'llm--semantic-index-form': SemanticIndexFormController },
    });

    await ctx.mount(`
      <div data-controller="llm--semantic-index-form"
           data-llm--semantic-index-form-defaults-value='${JSON.stringify(defaults)}'>
        <select aria-label="Model" data-action="change->llm--semantic-index-form#prefill">
          <option value=""></option>
          <option value="1">bge-m3@Scaleway</option>
          <option value="2">nomic@Local</option>
          <option value="3">custom@Local</option>
        </select>
        <input aria-label="Context length" data-llm--semantic-index-form-target="contextLength">
        <input aria-label="Dimensions" data-llm--semantic-index-form-target="dimensions">
      </div>
    `);

    model = ctx.screen.getByRole('combobox', { name: 'Model' });
    contextLength = ctx.screen.getByRole<HTMLInputElement>('textbox', { name: 'Context length' });
    dimensions = ctx.screen.getByRole<HTMLInputElement>('textbox', { name: 'Dimensions' });
  });

  afterEach(() => ctx.dispose());

  it('fills in the defaults of the selected model', () => {
    select('1');

    expect(contextLength).toHaveValue('8192');
    expect(dimensions).toHaveValue('1024');
  });

  it('follows the selection while the values are still the defaults', () => {
    select('1');
    select('2');

    expect(contextLength).toHaveValue('2048');
    expect(dimensions).toHaveValue('768');
  });

  it('keeps a value that was typed before selecting a model', () => {
    contextLength.value = '4096';

    select('1');

    expect(contextLength).toHaveValue('4096');
    expect(dimensions).toHaveValue('1024');
  });

  it('keeps a value that was typed over a default', () => {
    select('1');
    dimensions.value = '512';

    select('2');

    expect(contextLength).toHaveValue('2048');
    expect(dimensions).toHaveValue('512');
  });

  it('clears a default when the next model has none', () => {
    select('1');
    select('3');

    expect(contextLength).toHaveValue('');
    expect(dimensions).toHaveValue('');
  });

  it('clears a default when the selection is cleared', () => {
    select('1');
    select('');

    expect(contextLength).toHaveValue('');
    expect(dimensions).toHaveValue('');
  });
});
