// -- copyright
// OpenProject is an open source project management software.
// Copyright (C) 2012-2021 the OpenProject GmbH
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
// along with this program; if not, write to the Free Software
// Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
//
// See COPYRIGHT and LICENSE files for more details.
//++

import { APIv3GettableResource } from 'core-app/core/apiv3/paths/apiv3-resource';
import { Observable } from 'rxjs';
import { HttpClient } from '@angular/common/http';
import { InjectField } from 'core-app/shared/helpers/angular/inject-field.decorator';
import { InAppNotification } from 'core-app/core/state/in-app-notifications/in-app-notification.model';

export class Apiv3NotificationPaths extends APIv3GettableResource<InAppNotification> {
  @InjectField() http:HttpClient;

  public markRead():Observable<unknown> {
    return this
      .http
      .post(
        `${this.path}/read_ian`,
        {},
        {
          withCredentials: true,
          responseType: 'json',
        },
      );
  }

  public markUnread():Observable<unknown> {
    return this
      .http
      .post(
        `${this.path}/unread_ian`,
        {},
        {
          withCredentials: true,
          responseType: 'json',
        },
      );
  }
}
