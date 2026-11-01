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

# A server LLM features can talk to: where it lives, which dialect it speaks and
# how to authenticate against it.
#
# A provider stays stored when another one is activated, so an administrator can
# switch back without entering its values again. The active provider is the one
# +LlmConnection.active_connection+ points at.
class InferenceProvider < ApplicationRecord
  HEADER_NAME_TOKEN = /\A[!#$%&'*+\-.^_`|~0-9A-Za-z]+\z/

  has_many :llm_connections, dependent: :restrict_with_error
  has_many :embedding_models, dependent: :restrict_with_error
  has_many :health_reports, as: :subject, dependent: :delete_all

  # Only trailing whitespace and slashes are removed. The /v1 segment is
  # deliberately not added or stripped: silently rewriting an administrator's
  # URL makes the eventual failure harder to diagnose, so a wrong shape is
  # reported by the probe instead.
  normalizes :base_url, with: ->(url) { url.strip.chomp("/") }

  validates :base_url, presence: true
  validate :base_url_is_absolute_http, if: -> { base_url.present? }
  # The title defaults to the URL's host, so a URL error already explains a blank one.
  validates :title, presence: true, unless: -> { errors.include?(:base_url) }
  # Not only the contract's: the environment seeder and any direct write reach
  # the model alone, and an unknown format is an UnsupportedFormat raised at read
  # time rather than an error at write time.
  validates :api_format, inclusion: { in: Llm::Adapters::FORMATS }
  validate :custom_headers_are_flat_strings

  def active? = llm_connections.active.exists?

  # A key assigned but not saved, as after a failed update, is not stored.
  def api_key_stored? = persisted? && api_key_in_database.present?

  # Bypasses the contract: removing a credential must always be possible, even
  # against a server that would reject the resulting unauthenticated probe.
  def remove_api_key!
    transaction do
      update_columns(api_key: nil, updated_at: Time.current)
      release_from_environment!
    end
  end

  def release_from_environment!
    llm_connections.active.find_each(&:release_from_environment!)
  end

  # Never the whole URL: its userinfo or query string can carry a credential.
  def host_and_port
    uri = URI.parse(base_url.to_s)
    return if uri.host.blank?

    uri.port == uri.default_port ? uri.host : "#{uri.host}:#{uri.port}"
  rescue URI::InvalidURIError
    nil
  end

  def base_url_without_credentials
    uri = URI.parse(base_url)
    uri.user = nil
    uri.query = nil
    uri.fragment = nil
    uri.to_s
  rescue URI::InvalidURIError
    nil
  end

  private

  def base_url_is_absolute_http
    uri = URI.parse(base_url)
    return if uri.is_a?(URI::HTTP) && uri.host.present?

    errors.add(:base_url, :invalid_url)
  rescue URI::InvalidURIError
    errors.add(:base_url, :invalid_url)
  end

  # The value goes into Faraday's header serialization unchanged, where a nested
  # hash or a non-string fails at request time rather than at save time.
  def custom_headers_are_flat_strings
    return if custom_headers.blank?

    return errors.add(:custom_headers, :invalid) unless custom_headers.is_a?(Hash)

    return if custom_headers.all? { |name, value| header_pair?(name, value) }

    errors.add(:custom_headers, :invalid)
  end

  def header_pair?(name, value)
    name.is_a?(String) && name.match?(HEADER_NAME_TOKEN) &&
      value.is_a?(String) && !value.match?(/[[:cntrl:]]/)
  end
end
