require "time"
require "openssl"
require "base64"

module Fastlane
  module Helper
    class Uploader
      HOST = "https://public-api.rustore.ru".freeze
      API_VERSION = "/public/v1".freeze
      REQUEST_HEADERS = {
        "Accept": "application/json"
      }.freeze

      def self.authorize(company_id, private_key, timeout = 0)
        timestamp = Time.at(Time.now.to_i - 10).iso8601
        signature_data = "#{company_id}#{timestamp}"
        private_key = "-----BEGIN RSA PRIVATE KEY-----\n#{private_key}\n-----END RSA PRIVATE KEY-----"
        signature = OpenSSL::PKey::RSA.new(private_key).sign(OpenSSL::Digest.new("SHA512"), signature_data)
        signature_hex = Base64.encode64(signature)

        body = {
          companyId: company_id,
          timestamp: timestamp,
          signature: signature_hex
        }
        headers = {
          "Content-Type": "application/json"
        }.merge(REQUEST_HEADERS)

        begin
          connection = Faraday.new(HOST)
          response = connection.post("/public/auth") do |req|
            req.headers = headers
            req.body = body.to_json
            req.options.timeout = timeout if timeout.positive?
          end

          response_data = JSON.parse(response.body)

          if response.status == 200
            token = response_data["body"]["jwe"]
            time = response_data["body"]["ttl"]

            Helper.auth_data.setup(token, time)
            UI.message("Received a new authorization token. Current time: #{Helper.auth_data.created_at}, time to live: #{Helper.auth_data.time}")
          else
            request_error(response_data)
          end
        rescue StandardError => ex
          UI.user_error!("Authorization failed: #{ex}")
        end
      end

      def self.create_draft(data, timeout = 0)
        check_auth_token

        body = {
          appName: data[:app_name],
          shortDescription: data[:short_description],
          fullDescription: data[:full_description],
          whatsNew: data[:changelog],
          publishType: data[:publish_type],
          publishDateTime: data[:publish_date_time]
        }

        begin
          connection = Faraday.new(HOST)
          response = connection.post("#{API_VERSION}/application/#{data[:package]}/version") do |req|
            req.headers = build_headers(Helper.auth_data.token)
            req.body = body.to_json
            req.options.timeout = timeout if timeout.positive?
          end

          response_data = JSON.parse(response.body)
          request_error(response_data) if response.status != 200

          response_data["body"]
        rescue StandardError => ex
          UI.user_error!("Draft creation failed: #{ex}")
        end
      end

      def self.remove_draft(data, timeout = 0)
        check_auth_token

        begin
          connection = Faraday.new(HOST)
          response = connection.delete("#{API_VERSION}/application/#{data[:package]}/version/#{data[:version]}") do |req|
            req.headers = build_headers(Helper.auth_data.token)
            req.options.timeout = timeout if timeout.positive?
          end

          response_data = JSON.parse(response.body)
          request_error(response_data) if response.status != 200
        rescue StandardError => ex
          UI.user_error!("Draft removal failed: #{ex}")
        end
      end

      def self.get_active_version(package_id, timeout = 0)
        check_auth_token

        begin
          connection = Faraday.new(HOST)
          response = connection.get("#{API_VERSION}/application/#{package_id}/version") do |req|
            req.headers = build_headers(Helper.auth_data.token)
            req.options.timeout = timeout if timeout.positive?
          end

          response_data = JSON.parse(response.body)
          request_error(response_data) if response.status != 200

          versions = response_data["body"]["content"]
          version_obj = versions.find { |x| x["versionStatus"] == "DRAFT" }

          !version_obj.nil? ? version_obj["versionId"] : -1
        rescue StandardError => ex
          UI.user_error!("Can't get active draft version: #{ex}")
        end
      end

      def self.upload_icon(data, timeout = 0)
        check_auth_token

        file_path = data[:file]
        mime_type = Helper::ImageValidator.mime_type(file_path)

        body = {
          file: Faraday::Multipart::FilePart.new(file_path, mime_type)
        }
        headers = build_headers(Helper.auth_data.token)
        headers["Content-Type"] = "multipart/form-data"

        begin
          connection = Faraday.new(HOST) do |con|
            con.request :multipart
          end
          response = connection.post("#{API_VERSION}/application/#{data[:package]}/version/#{data[:version]}/image/icon") do |req|
            req.headers = headers
            req.body = body
            req.options.timeout = timeout if timeout.positive?
          end

          response_data = JSON.parse(response.body)
          request_error(response_data) if response.status != 200
        rescue StandardError => ex
          UI.user_error!("Icon uploading failed: #{ex}")
        end
      end

      def self.upload_screenshot(data, timeout = 0)
        check_auth_token

        file_path = data[:file]
        mime_type = Helper::ImageValidator.mime_type(file_path)

        body = {
          file: Faraday::Multipart::FilePart.new(file_path, mime_type)
        }
        headers = build_headers(Helper.auth_data.token)
        headers["Content-Type"] = "multipart/form-data"

        begin
          connection = Faraday.new(HOST) do |con|
            con.request :multipart
          end
          response = connection.post("#{API_VERSION}/application/#{data[:package]}/version/#{data[:version]}/image/screenshot/#{data[:orientation]}/#{data[:ordinal]}") do |req|
            req.headers = headers
            req.body = body
            req.options.timeout = timeout if timeout.positive?
          end

          response_data = JSON.parse(response.body)
          request_error(response_data) if response.status != 200
        rescue StandardError => ex
          UI.user_error!("Screenshot uploading failed: #{ex}")
        end
      end

      def self.upload_package(data, is_aab, timeout = 0)
        check_auth_token

        body = {
          file: Faraday::Multipart::FilePart.new(data[:file], "application/octet-stream")
        }
        headers = build_headers(Helper.auth_data.token)
        headers["Content-Type"] = "multipart/form-data"

        begin
          connection = Faraday.new(HOST) do |con|
            con.request :multipart
          end
          package_type = is_aab ? "aab" : "apk"
          response = connection.post("#{API_VERSION}/application/#{data[:package]}/version/#{data[:version]}/#{package_type}") do |req|
            req.headers = headers
            req.body = body
            req.options.timeout = timeout if timeout.positive?

            unless is_aab
              req.params = {
                servicesType: data[:services_type],
                isMainApk: data[:is_main_apk]
              }
            end
          end

          response_data = JSON.parse(response.body)
          request_error(response_data) if response.status != 200
        rescue StandardError => ex
          UI.user_error!("Package uploading failed: #{ex}")
        end
      end

      def self.commit(data, timeout = 0)
        check_auth_token

        query = {
          priorityUpdate: data[:priority_update]
        }

        begin
          connection = Faraday.new(HOST)
          response = connection.post("#{API_VERSION}/application/#{data[:package]}/version/#{data[:version]}/commit") do |req|
            req.headers = build_headers(Helper.auth_data.token)
            req.params = query
            req.options.timeout = timeout if timeout.positive?
          end

          response_data = JSON.parse(response.body)
          request_error(response_data) if response.status != 200
        rescue StandardError => ex
          UI.user_error!("Draft committing failed: #{ex}")
        end
      end

      def self.check_auth_token
        return if Helper.auth_data.valid?

        UI.user_error!("No authorization data has provided. You need to call `rustore_credentials` action first.") unless
          Helper.auth_data.token?
        UI.important("Authorization token is not valid. Renewing...")
        authorize(Helper.config.company_id, Helper.config.private_key)
      end

      def self.build_headers(auth_token)
        {
          "Public-Token": auth_token,
          "Content-Type": "application/json"
        }.merge(REQUEST_HEADERS)
      end

      def self.request_error(data)
        error_code = data["code"]
        error_description = data["message"]
        UI.user_error!("Request returned the error.\nCode: #{error_code}\nDescription: #{error_description}")
      end

      public_class_method(:authorize)
      public_class_method(:create_draft)
      public_class_method(:remove_draft)
      public_class_method(:get_active_version)
      public_class_method(:upload_icon)
      public_class_method(:upload_screenshot)
      public_class_method(:upload_package)
      public_class_method(:commit)

      private_class_method(:check_auth_token)
      private_class_method(:build_headers)
      private_class_method(:request_error)

      private_constant(:HOST)
      private_constant(:API_VERSION)
      private_constant(:REQUEST_HEADERS)
    end
  end
end
