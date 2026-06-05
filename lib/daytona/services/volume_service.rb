# frozen_string_literal: true

# Copyright 2025 Daytona Platforms Inc.
# SPDX-License-Identifier: Apache-2.0

module Daytona
  module Services
    # Volume management service
    #
    # Provides methods for managing Daytona Volumes (shared storage).
    #
    # @example
    #   # Create a volume
    #   volume = client.volume.create("my-volume")
    #
    #   # List volumes
    #   volumes = client.volume.list
    class VolumeService
      # @param http_client [API::HttpClient] HTTP client for API calls
      def initialize(http_client)
        @http_client = http_client
      end

      # List all volumes
      #
      # @return [Array<Models::Volume>] List of volumes
      #
      # @example
      #   volumes = client.volume.list
      #   volumes.each { |v| puts "#{v.name}: #{v.state}" }
      def list
        response = @http_client.get("/volumes")
        # The endpoint returns a bare JSON array; older builds wrapped it in
        # { items: [...] }. Indexing a String key into an Array raises, so
        # branch on the type before reaching for :items.
        items = response.is_a?(Array) ? response : (response["items"] || response[:items] || [])
        items.map { |v| Models::Volume.from_hash(v) }
      end

      # Get a volume by ID
      #
      # @param volume_id [String] Volume ID
      # @return [Models::Volume] The volume
      #
      # @raise [NotFoundError] If volume is not found
      def get(volume_id)
        response = @http_client.get("/volumes/#{volume_id}")
        Models::Volume.from_hash(response)
      end

      # Create a new volume
      #
      # @param name [String] Volume name
      # @return [Models::Volume] The created volume
      #
      # @example
      #   volume = client.volume.create("shared-data")
      def create(name)
        response = @http_client.post("/volumes", body: { name: name })
        Models::Volume.from_hash(response)
      end

      # Delete a volume
      #
      # @param volume_id [String] Volume ID
      #
      # @example
      #   client.volume.delete("vol-123")
      def delete(volume_id)
        @http_client.delete("/volumes/#{volume_id}")
      end

      # Get or create a volume by name
      #
      # If a volume with the given name exists, returns it.
      # Otherwise, creates a new volume.
      #
      # @param name [String] Volume name
      # @return [Models::Volume] The volume
      #
      # @example
      #   volume = client.volume.get_or_create("my-data")
      def get_or_create(name)
        volumes = list
        existing = volumes.find { |v| v.name == name }
        return existing if existing

        create(name)
      end
    end
  end
end
