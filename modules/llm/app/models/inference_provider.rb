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

# A server LLM features can talk to: where it lives, which dialect it speaks, how
# to authenticate against it and which models it offers. All providers are usable
# at the same time, and a model row says which one it belongs to.
class InferenceProvider < ApplicationRecord
  HEADER_NAME_TOKEN = /\A[!#$%&'*+\-.^_`|~0-9A-Za-z]+\z/

  has_many :models, class_name: "LlmModel", dependent: :delete_all
  has_many :capability_verdicts, class_name: "LlmCapabilityVerdict", dependent: :delete_all
  has_many :health_reports, as: :subject, dependent: :delete_all

  scope :by_title, -> { order(:title, :id) }

  # Only trailing whitespace and slashes are removed. The /v1 segment is
  # deliberately not added or stripped: silently rewriting an administrator's
  # URL makes the eventual failure harder to diagnose, so a wrong shape is
  # reported by the probe instead.
  normalizes :base_url, with: ->(url) { url.strip.chomp("/") }

  validates :base_url, presence: true
  validate :base_url_is_absolute_http, if: -> { base_url.present? }
  # The title defaults to the URL's host, so a URL error already explains a blank one.
  validates :title, presence: true, unless: -> { errors.include?(:base_url) }
  validates :title, uniqueness: true
  # Not only the contract's: the environment seeder and any direct write reach
  # the model alone, and an unknown format is an UnsupportedFormat raised at read
  # time rather than an error at write time.
  validates :api_format, inclusion: { in: Llm::Adapters::FORMATS }
  validate :custom_headers_are_flat_strings

  # A key assigned but not saved, as after a failed update, is not stored.
  def api_key_stored? = persisted? && api_key_in_database.present?

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

  # Every model that can be addressed today: discovered and still offered, plus
  # anything an administrator entered by hand.
  def available_model_ids
    models.active.by_identifier.pluck(:external_id)
  end

  def available_models
    models.active.by_identifier
  end

  def chat_models
    available_models.where(external_id: chat_model_ids)
  end

  def embedding_models
    available_models.where(external_id: embedding_model_ids)
  end

  def embedding_capable_model_ids
    capability_verdicts.for_capability(:embeddings).where(state: "supported").pluck(:model_id)
  end

  def embedding_model_ids = available_model_ids & embedding_capable_model_ids

  def chat_model_ids = available_model_ids - embedding_model_ids

  def server_flavor
    options["server_flavor"].presence&.to_sym
  end

  # Whether a health check run may spend a real completion.
  #
  # Not a column: it describes the run, not the provider. An administrator asking
  # to test the provider wants it; the scheduled re-check leaves it off so that a
  # paid provider is not billed four times a day.
  attr_accessor :deep_health_check

  def deep_health_check? = ActiveModel::Type::Boolean.new.cast(deep_health_check).present?

  def latest_health_report
    health_reports.order(created_at: :asc).last
  end

  # Feeds the downloadable health report. Deliberately excludes api_key *and*
  # custom_headers: a gateway header routinely carries a second credential, as
  # can the userinfo or query string of base_url.
  def non_confidential_configuration
    {
      base_url: base_url_without_credentials,
      api_format:,
      llm_features_enabled: Setting.llm_features_enabled?,
      server_flavor: server_flavor&.to_s,
      last_synced_at: last_synced_at&.utc&.iso8601,
      last_connected_at: last_connected_at&.utc&.iso8601,
      model_count: models.count,
      manual_model_count: models.where(manual: true).count
    }
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
