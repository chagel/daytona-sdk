# frozen_string_literal: true

# Copyright 2025 Daytona Platforms Inc.
# SPDX-License-Identifier: Apache-2.0

require "faraday"
require "faraday/multipart"
require "faraday/net_http_persistent"
require "json"
require "stringio"

module Daytona
  module API
    # HTTP client wrapper for Daytona API communication
    #
    # Handles authentication, request/response processing, and error handling.
    class HttpClient
      # Default request timeout in seconds
      DEFAULT_TIMEOUT = 120

      # @return [String] Base URL for API requests
      attr_reader :base_url

      # Initialize a new HTTP client
      #
      # @param base_url [String] Base URL for API requests
      # @param api_key [String, nil] API key for authentication
      # @param jwt_token [String, nil] JWT token for authentication
      # @param organization_id [String, nil] Organization ID for JWT auth
      def initialize(base_url:, api_key: nil, jwt_token: nil, organization_id: nil)
        # Ensure base_url ends with / to prevent path replacement by URI.join
        @base_url = base_url.end_with?("/") ? base_url : "#{base_url}/"
        @api_key = api_key
        @jwt_token = jwt_token
        @organization_id = organization_id

        @connection = build_connection
      end

      # Perform a GET request
      #
      # @param path [String] API endpoint path
      # @param params [Hash] Query parameters
      # @param timeout [Integer] Request timeout in seconds
      # @return [Hash, Array, String] Parsed response body
      def get(path, params: {}, timeout: DEFAULT_TIMEOUT)
        handle_response do
          @connection.get(normalize_path(path)) do |req|
            req.params = params
            req.options.timeout = timeout
          end
        end
      end

      # Perform a POST request
      #
      # @param path [String] API endpoint path
      # @param body [Hash, nil] Request body
      # @param timeout [Integer] Request timeout in seconds
      # @return [Hash, Array, String] Parsed response body
      def post(path, body: nil, timeout: DEFAULT_TIMEOUT)
        handle_response do
          @connection.post(normalize_path(path)) do |req|
            req.body = body.to_json if body
            req.options.timeout = timeout
          end
        end
      end

      # Perform a PUT request
      #
      # @param path [String] API endpoint path
      # @param body [Hash, nil] Request body
      # @param timeout [Integer] Request timeout in seconds
      # @return [Hash, Array, String] Parsed response body
      def put(path, body: nil, timeout: DEFAULT_TIMEOUT)
        handle_response do
          @connection.put(normalize_path(path)) do |req|
            req.body = body.to_json if body
            req.options.timeout = timeout
          end
        end
      end

      # Perform a PATCH request
      #
      # @param path [String] API endpoint path
      # @param body [Hash, nil] Request body
      # @param timeout [Integer] Request timeout in seconds
      # @return [Hash, Array, String] Parsed response body
      def patch(path, body: nil, timeout: DEFAULT_TIMEOUT)
        handle_response do
          @connection.patch(normalize_path(path)) do |req|
            req.body = body.to_json if body
            req.options.timeout = timeout
          end
        end
      end

      # Perform a DELETE request
      #
      # @param path [String] API endpoint path
      # @param timeout [Integer] Request timeout in seconds
      # @return [Hash, Array, String, nil] Parsed response body
      def delete(path, timeout: DEFAULT_TIMEOUT)
        handle_response do
          @connection.delete(normalize_path(path)) do |req|
            req.options.timeout = timeout
          end
        end
      end

      # Upload a file using multipart form
      #
      # @param path [String] API endpoint path
      # @param file_path [String] Local file path
      # @param field_name [String] Form field name for the file
      # @param additional_fields [Hash] Additional form fields
      # @param timeout [Integer] Request timeout in seconds
      # @return [Hash, Array, String] Parsed response body
      def upload_file(path, file_path:, field_name: "file", additional_fields: {}, timeout: 1800)
        payload = additional_fields.merge(
          field_name => Faraday::Multipart::FilePart.new(
            file_path,
            "application/octet-stream",
            File.basename(file_path)
          )
        )

        handle_response do
          multipart_connection.post(normalize_path(path)) do |req|
            req.body = payload
            req.options.timeout = timeout
          end
        end
      end

      # Upload raw bytes using multipart form data
      #
      # @param path [String] API endpoint path
      # @param content [String] File content as bytes
      # @param filename [String] Filename
      # @param content_type [String] Content type
      # @param timeout [Integer] Request timeout in seconds
      # @return [Hash, Array, String] Parsed response body
      def upload_bytes(path, content:, filename: "file", content_type: "application/octet-stream", timeout: 1800)
        # Create a StringIO to simulate a file for multipart upload
        io = StringIO.new(content)

        payload = {
          file: Faraday::Multipart::FilePart.new(
            io,
            content_type,
            filename
          )
        }

        handle_response do
          multipart_connection.post(normalize_path(path)) do |req|
            req.body = payload
            req.options.timeout = timeout
          end
        end
      end

      # Download a file
      #
      # @param path [String] API endpoint path
      # @param timeout [Integer] Request timeout in seconds
      # @return [String] Raw response body (binary)
      def download_file(path, timeout: 1800)
        response = @connection.get(normalize_path(path)) do |req|
          req.options.timeout = timeout
        end

        handle_error(response) unless response.success?
        response.body
      end

      private

      # Normalize path by removing leading slash to work with URI.join
      #
      # @param path [String] API endpoint path
      # @return [String] Normalized path without leading slash
      def normalize_path(path)
        path.to_s.sub(%r{^/+}, "")
      end

      def build_connection
        # Check if SSL verification should be disabled (for MITM proxies)
        ssl_verify = ENV.fetch("DAYTONA_SSL_VERIFY", "true").downcase != "false"

        ssl_options = { verify: ssl_verify }

        Faraday.new(url: @base_url, ssl: ssl_options) do |conn|
          conn.request :json
          conn.response :json, content_type: /\bjson$/
          conn.adapter :net_http_persistent

          conn.headers["Authorization"] = "Bearer #{auth_token}"
          conn.headers["Content-Type"] = "application/json"
          conn.headers["Accept"] = "application/json"
          conn.headers["X-Daytona-Source"] = "ruby-sdk"
          conn.headers["X-Daytona-SDK-Version"] = Daytona::VERSION

          if @organization_id && @api_key.nil?
            conn.headers["X-Daytona-Organization-ID"] = @organization_id
          end
        end
      end

      def multipart_connection
        @multipart_connection ||= Faraday.new(url: @base_url) do |conn|
          conn.request :multipart
          conn.response :json, content_type: /\bjson$/
          conn.adapter :net_http_persistent

          conn.headers["Authorization"] = "Bearer #{auth_token}"
          conn.headers["Accept"] = "application/json"
          conn.headers["X-Daytona-Source"] = "ruby-sdk"
          conn.headers["X-Daytona-SDK-Version"] = Daytona::VERSION

          if @organization_id && @api_key.nil?
            conn.headers["X-Daytona-Organization-ID"] = @organization_id
          end
        end
      end

      def auth_token
        @api_key || @jwt_token
      end

      def handle_response
        response = yield
        handle_error(response) unless response.success?

        body = response.body
        content_type = response.headers["content-type"] rescue "unknown"

        # Log response details for debugging
        if defined?(Rails) && Rails.logger
          Rails.logger.debug "[Daytona::HttpClient] Response status=#{response.status}, content-type=#{content_type}, body_type=#{body.class}"
        end

        # If body is a string but should be JSON, try to parse it
        if body.is_a?(String) && !body.empty?
          if content_type&.include?("json") || body.start_with?('{', '[')
            begin
              parsed = JSON.parse(body)
              Rails.logger.debug "[Daytona::HttpClient] Manually parsed JSON response" if defined?(Rails)
              return parsed
            rescue JSON::ParserError => e
              Rails.logger.warn "[Daytona::HttpClient] Failed to parse as JSON: #{e.message}" if defined?(Rails)
            end
          end

          # Still a string - log for debugging
          Rails.logger.warn "[Daytona::HttpClient] Unexpected string response (content-type: #{content_type}): #{body[0..200]}" if defined?(Rails)
        end

        body
      rescue Faraday::TimeoutError => e
        raise Daytona::TimeoutError, "Request timed out: #{e.message}"
      rescue Faraday::ConnectionFailed => e
        raise Daytona::DaytonaError, "Connection failed: #{e.message}"
      end

      def handle_error(response)
        message = extract_error_message(response)
        status = response.status
        headers = response.headers.to_h

        case status
        when 401, 403
          raise Daytona::AuthenticationError.new(message, status_code: status, headers: headers)
        when 404
          raise Daytona::NotFoundError.new(message, status_code: status, headers: headers)
        when 429
          raise Daytona::RateLimitError.new(message, status_code: status, headers: headers)
        else
          raise Daytona::DaytonaError.new(message, status_code: status, headers: headers)
        end
      end

      def extract_error_message(response)
        body = response.body
        return body["message"] if body.is_a?(Hash) && body["message"]
        return body["error"] if body.is_a?(Hash) && body["error"]
        return body.to_s if body.is_a?(String) && !body.empty?

        "HTTP #{response.status} error"
      end
    end
  end
end
