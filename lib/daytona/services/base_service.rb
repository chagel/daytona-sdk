# frozen_string_literal: true

# Copyright 2025 Daytona Platforms Inc.
# SPDX-License-Identifier: Apache-2.0

module Daytona
  module Services
    # Base class for all Sandbox services
    #
    # Provides common functionality for toolbox API communication.
    class BaseService
      # @param http_client [API::HttpClient] HTTP client
      # @param sandbox_id [String] Sandbox ID
      # @param get_toolbox_url [Proc] Function to get toolbox URL
      def initialize(http_client:, sandbox_id:, get_toolbox_url:)
        @http_client = http_client
        @sandbox_id = sandbox_id
        @get_toolbox_url = get_toolbox_url
        @toolbox_url = nil
        @toolbox_client = nil
      end

      protected

      # Ensure toolbox URL is initialized.
      #
      # Toolbox calls go through the runner's toolbox proxy, addressed per
      # sandbox: {proxyToolboxUrl}/{sandbox_id} (e.g.
      # https://proxy.app.daytona.io/toolbox/<id>). @get_toolbox_url returns the
      # proxy base; we append the sandbox id, matching Sandbox#ensure_toolbox_url!.
      # The legacy {api_base}/toolbox/{id}/toolbox gateway still serves some
      # routes but 404s newer ones (e.g. session command input).
      def ensure_toolbox_url!
        return if @toolbox_url

        base = @get_toolbox_url.call
        base = "#{base}/" unless base.end_with?("/")
        @toolbox_url = "#{base}#{@sandbox_id}"
      end

      # Get toolbox HTTP client
      #
      # @return [API::HttpClient]
      def toolbox_client
        ensure_toolbox_url!
        @toolbox_client ||= API::HttpClient.new(
          base_url: @toolbox_url,
          api_key: @http_client.instance_variable_get(:@api_key),
          jwt_token: @http_client.instance_variable_get(:@jwt_token),
          organization_id: @http_client.instance_variable_get(:@organization_id)
        )
      end

      # Perform GET request to toolbox API
      #
      # @param path [String] API path
      # @param params [Hash] Query parameters
      # @param timeout [Integer] Request timeout
      # @return [Hash, Array, String] Response
      def toolbox_get(path, params: {}, timeout: 120)
        toolbox_client.get(path, params: params, timeout: timeout)
      end

      # Perform POST request to toolbox API
      #
      # @param path [String] API path
      # @param body [Hash, nil] Request body
      # @param timeout [Integer] Request timeout
      # @return [Hash, Array, String] Response
      def toolbox_post(path, body: nil, timeout: 120)
        toolbox_client.post(path, body: body, timeout: timeout)
      end

      # Perform PUT request to toolbox API
      #
      # @param path [String] API path
      # @param body [Hash, nil] Request body
      # @param timeout [Integer] Request timeout
      # @return [Hash, Array, String] Response
      def toolbox_put(path, body: nil, timeout: 120)
        toolbox_client.put(path, body: body, timeout: timeout)
      end

      # Perform DELETE request to toolbox API
      #
      # @param path [String] API path
      # @param timeout [Integer] Request timeout
      # @return [Hash, Array, String, nil] Response
      def toolbox_delete(path, timeout: 120)
        toolbox_client.delete(path, timeout: timeout)
      end

      # Upload file to toolbox API
      #
      # @param path [String] API path
      # @param file_path [String] Local file path
      # @param timeout [Integer] Request timeout
      # @return [Hash, Array, String] Response
      def toolbox_upload(path, file_path:, timeout: 1800)
        toolbox_client.upload_file(path, file_path: file_path, timeout: timeout)
      end

      # Download file from toolbox API
      #
      # @param path [String] API path
      # @param timeout [Integer] Request timeout
      # @return [String] Binary content
      def toolbox_download(path, timeout: 1800)
        toolbox_client.download_file(path, timeout: timeout)
      end
    end
  end
end
