# frozen_string_literal: true

# Copyright 2025 Daytona Platforms Inc.
# SPDX-License-Identifier: Apache-2.0

module Daytona
  module Services
    # File system operations for Sandbox
    #
    # Provides methods for file and directory manipulation within the Sandbox.
    #
    # @example
    #   # Upload a file
    #   sandbox.fs.upload_file("local.txt", "/home/user/remote.txt")
    #
    #   # Read file content
    #   content = sandbox.fs.read_file_as_text("/home/user/file.txt")
    #
    #   # List directory
    #   files = sandbox.fs.list_files("/home/user")
    class FileSystem < BaseService
      # Create a folder
      #
      # @param path [String] Path to create
      # @param mode [String] File mode (e.g., "0755")
      #
      # @example
      #   sandbox.fs.create_folder("/home/user/new_dir", "0755")
      def create_folder(path, mode = "0755")
        toolbox_post("/files/folder", body: { path: path, mode: mode })
      end

      # Delete a file or directory
      #
      # @param path [String] Path to delete
      # @param recursive [Boolean] Delete recursively for directories
      #
      # @example
      #   sandbox.fs.delete_file("/home/user/old_file.txt")
      #   sandbox.fs.delete_file("/home/user/old_dir", recursive: true)
      def delete_file(path, recursive: false)
        params = { path: path }
        params[:recursive] = "true" if recursive
        toolbox_delete("/files?#{URI.encode_www_form(params)}")
      end

      # Download a file
      #
      # @param remote_path [String] Path in the Sandbox
      # @param local_path [String, nil] Local path to save (if nil, returns content)
      # @param timeout [Integer] Request timeout in seconds
      # @return [String, nil] File content if local_path is nil
      #
      # @example
      #   # Download to local file
      #   sandbox.fs.download_file("/home/user/file.txt", "local_copy.txt")
      #
      #   # Get content as string
      #   content = sandbox.fs.download_file("/home/user/file.txt")
      def download_file(remote_path, local_path = nil, timeout: 1800)
        encoded_path = URI.encode_www_form_component(remote_path)
        content = toolbox_download("/files/download?path=#{encoded_path}", timeout: timeout)

        if local_path
          File.binwrite(local_path, content)
          nil
        else
          content
        end
      end

      # Download multiple files
      #
      # @param files [Array<Hash>] Array of { remote_path:, local_path: } hashes
      # @param timeout [Integer] Request timeout per file
      #
      # @example
      #   sandbox.fs.download_files([
      #     { remote_path: "/home/user/a.txt", local_path: "a.txt" },
      #     { remote_path: "/home/user/b.txt", local_path: "b.txt" }
      #   ])
      def download_files(files, timeout: 1800)
        files.each do |file|
          download_file(file[:remote_path], file[:local_path], timeout: timeout)
        end
      end

      # Search for text in files
      #
      # @param path [String] Directory to search in
      # @param pattern [String] Search pattern (regex)
      # @return [Array<Hash>] Matching results with file paths and line numbers
      #
      # @example
      #   results = sandbox.fs.find_files("/home/user/project", "TODO")
      def find_files(path, pattern)
        response = toolbox_get("/files/find", params: { path: path, pattern: pattern })
        response["matches"] || response[:matches] || []
      end

      # Get file information
      #
      # @param path [String] File path
      # @return [Hash] File metadata (size, permissions, modified time, etc.)
      #
      # @example
      #   info = sandbox.fs.get_file_info("/home/user/file.txt")
      #   puts "Size: #{info['size']}"
      def get_file_info(path)
        encoded_path = URI.encode_www_form_component(path)
        toolbox_get("/files/info?path=#{encoded_path}")
      end

      # List files in a directory
      #
      # @param path [String] Directory path
      # @return [Array<Hash>] List of files and directories
      #
      # @example
      #   files = sandbox.fs.list_files("/home/user")
      #   files.each { |f| puts f['name'] }
      def list_files(path)
        encoded_path = URI.encode_www_form_component(path)
        response = toolbox_get("/files?path=#{encoded_path}")
        response["entries"] || response[:entries] || []
      end

      # Move/rename files
      #
      # @param source [String] Source path
      # @param destination [String] Destination path
      #
      # @example
      #   sandbox.fs.move_files("/home/user/old.txt", "/home/user/new.txt")
      def move_files(source, destination)
        toolbox_post("/files/move", body: { source: source, destination: destination })
      end

      # Replace text in files
      #
      # @param files [Array<String>] List of file paths
      # @param pattern [String] Pattern to find (regex)
      # @param new_value [String] Replacement value
      # @return [Hash] Results of replacements
      #
      # @example
      #   sandbox.fs.replace_in_files(
      #     ["/home/user/file1.txt", "/home/user/file2.txt"],
      #     "old_text",
      #     "new_text"
      #   )
      def replace_in_files(files, pattern, new_value)
        toolbox_post("/files/replace", body: {
          files: files,
          pattern: pattern,
          newValue: new_value,
        })
      end

      # Search for files by name pattern
      #
      # @param path [String] Directory to search in
      # @param pattern [String] Filename pattern (glob)
      # @return [Array<String>] List of matching file paths
      #
      # @example
      #   files = sandbox.fs.search_files("/home/user", "*.rb")
      def search_files(path, pattern)
        response = toolbox_get("/files/search", params: { path: path, pattern: pattern })
        response["files"] || response[:files] || []
      end

      # Set file permissions
      #
      # @param path [String] File path
      # @param mode [String, nil] File mode (e.g., "0644")
      # @param owner [String, nil] Owner name
      # @param group [String, nil] Group name
      #
      # @example
      #   sandbox.fs.set_file_permissions("/home/user/script.sh", mode: "0755")
      def set_file_permissions(path, mode: nil, owner: nil, group: nil)
        body = { path: path }
        body[:mode] = mode if mode
        body[:owner] = owner if owner
        body[:group] = group if group
        toolbox_post("/files/permissions", body: body)
      end

      # Upload a file
      #
      # @param source [String] Local file path or content as String
      # @param destination [String] Remote path in the Sandbox
      # @param timeout [Integer] Request timeout in seconds
      #
      # @example
      #   # Upload from file
      #   sandbox.fs.upload_file("local.txt", "/home/user/remote.txt")
      #
      #   # Upload content directly
      #   sandbox.fs.upload_file("Hello, World!", "/home/user/hello.txt")
      def upload_file(source, destination, timeout: 1800)
        encoded_path = URI.encode_www_form_component(destination)

        if File.exist?(source)
          toolbox_upload("/files/upload?path=#{encoded_path}", file_path: source, timeout: timeout)
        else
          # Source is content string
          toolbox_client.upload_bytes(
            "/files/upload?path=#{encoded_path}",
            content: source,
            filename: File.basename(destination),
            timeout: timeout
          )
        end
      end

      # Upload multiple files
      #
      # @param files [Array<Hash>] Array of { source:, destination: } hashes
      # @param timeout [Integer] Request timeout per file
      #
      # @example
      #   sandbox.fs.upload_files([
      #     { source: "a.txt", destination: "/home/user/a.txt" },
      #     { source: "b.txt", destination: "/home/user/b.txt" }
      #   ])
      def upload_files(files, timeout: 1800)
        files.each do |file|
          upload_file(file[:source], file[:destination], timeout: timeout)
        end
      end

      # Read file content as text
      #
      # @param path [String] File path
      # @return [String] File content
      #
      # @example
      #   content = sandbox.fs.read_file_as_text("/home/user/config.json")
      def read_file_as_text(path)
        download_file(path)
      end

      # Write text content to a file
      #
      # @param path [String] File path
      # @param content [String] Content to write
      # @param timeout [Integer] Request timeout
      #
      # @example
      #   sandbox.fs.write_file("/home/user/output.txt", "Hello, World!")
      def write_file(path, content, timeout: 1800)
        upload_file(content, path, timeout: timeout)
      end
    end
  end
end
