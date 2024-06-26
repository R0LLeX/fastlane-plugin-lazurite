require "fastlane/action"
require_relative "../helper/uploader"

module Fastlane
  module Actions
    class RustoreCredentialsAction < Action
      def self.run(params)
        private_key = ""

        if params.values.include?(:private_key_file) && !params[:private_key_file].nil?
          private_key = File.read(File.expand_path(params[:private_key_file]))
        elsif params.values.include?(:private_key) && !params[:private_key].nil?
          private_key = params[:private_key]
        else
          UI.user_error!("You need to provide the private API key")
        end

        private_key = private_key.strip
        Helper::Uploader.authorize(params[:key_id], private_key)
        UI.success("Credentials for RuStore account are successfully saved for further actions")
      end

      def self.description
        "Sets RuStore account credentials needed for authorization"
      end

      def self.authors
        ["CheeryLee"]
      end

      def self.is_supported?(platform)
        [:android].include?(platform)
      end

      def self.output
        [
          ["RUSTORE_KEY_ID", "ID of private key"],
          ["RUSTORE_PRIVATE_KEY_FILE", "The path to file where private API key is located"],
          ["RUSTORE_PRIVATE_KEY", "The private API key content (instead of file)"]
        ]
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(
            key: :key_id,
            env_name: "RUSTORE_KEY_ID",
            description: "ID of private key",
            optional: false,
            type: String,
            verify_block: proc do |value|
              UI.user_error!("Private key ID can't be empty") unless value && !value.empty?
            end
          ),
          FastlaneCore::ConfigItem.new(
            key: :private_key_file,
            env_name: "RUSTORE_PRIVATE_KEY_FILE",
            description: [
              "The path to file where private API key is located.",
              "Either use it or provide the raw key content with `private_key` option"
            ].join("\n"),
            optional: true,
            conflicting_options: [:private_key],
            type: String,
            verify_block: proc do |value|
              UI.user_error!("Path to the private API key file is invalid") unless value && !value.empty?
              UI.user_error!("There is no any file that provided in API key file path") unless
                File.exist?(File.expand_path(value))
            end
          ),
          FastlaneCore::ConfigItem.new(
            key: :private_key,
            env_name: "RUSTORE_PRIVATE_KEY",
            description: [
              "The private API key content.",
              "Either use it or provide the key content in a file with `private_key_file` option"
            ].join("\n"),
            optional: true,
            conflicting_options: [:private_key_file],
            sensitive: true,
            type: String,
            verify_block: proc do |value|
              UI.user_error!("API key can't be empty") unless value && !value.empty?
            end
          )
        ]
      end

      def self.category
        :misc
      end
    end
  end
end
