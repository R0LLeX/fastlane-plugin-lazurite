require "fastlane/action"
require_relative "../helper/enums"

module Fastlane
  module Actions
    class UploadToRustoreAction < Action
      SHORT_DESCRIPTION_LENGTH = 80
      FULL_DESCRIPTION_LENGTH = 4000
      CHANGELOG_LENGTH = 500
      SCREENSHOTS_COUNT = 10
      APP_CATEGORIES_COUNT = 2

      APK_ONLY_PACKAGES_COUNT = 10
      APK_PACKAGES_COUNT = 8
      AAB_PACKAGES_COUNT = 1

      def self.run(params)
        UI.user_error!("Publish time must be provided while uploading with DELAYED type of publishing") if
          params.values[:publish_type] == Helper::PublishType::DELAYED && params.values[:publish_date_time].nil?
        UI.user_error!("App categories validation failed. Check the errors above.") unless validate_app_categories(params)
        UI.user_error!("No APK or AAB packages were specified") if params.values.include?(:apk_paths) && !params.values[:apk_paths].nil? && params.values[:apk_paths].empty? ||
                                                                   params.values.include?(:aab_paths) && !params.values[:aab_paths].nil? && params.values[:aab_paths].empty?

        version = create_draft(params)
        upload_apk(params, version)
        upload_aab(params, version)
        upload_icon(params, version)
        upload_screenshots(params, version)
        commit(params, version)
      end

      def self.description
        "Uploads app metadata, screenshots, icons and app bundles to RuStore"
      end

      def self.authors
        ["CheeryLee"]
      end

      def self.is_supported?(platform)
        [:android].include?(platform)
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(
            key: :package_name,
            env_name: "RUSTORE_PACKAGE_NAME",
            description: "The package name of the application to use",
            optional: false,
            type: String,
            verify_block: proc do |value|
              UI.user_error!("Package name can't be empty") unless value && !value.empty?
            end
          ),
          FastlaneCore::ConfigItem.new(
            key: :app_name,
            env_name: "RUSTORE_APP_NAME",
            description: "The custom application name",
            optional: true,
            type: String,
            verify_block: proc do |value|
              UI.user_error!("Custom application name can't be empty") unless value && !value.empty?
            end
          ),
          FastlaneCore::ConfigItem.new(
            key: :short_description,
            description: "The short application description text",
            optional: true,
            type: String,
            verify_block: proc do |value|
              UI.important("Short description length is more than #{SHORT_DESCRIPTION_LENGTH} characters. The rest part will be ended with ellipsis.") if
                !value.nil? && value.length > SHORT_DESCRIPTION_LENGTH
            end
          ),
          FastlaneCore::ConfigItem.new(
            key: :full_description,
            description: "The full application description text",
            optional: true,
            type: String,
            verify_block: proc do |value|
              UI.important("Full description length is more than #{FULL_DESCRIPTION_LENGTH} characters. The rest part will be ended with ellipsis.") if
                !value.nil? && value.length > FULL_DESCRIPTION_LENGTH
            end
          ),
          FastlaneCore::ConfigItem.new(
            key: :changelog,
            description: "The changelog text",
            optional: true,
            type: String,
            verify_block: proc do |value|
              UI.important("Changelog length is more than #{CHANGELOG_LENGTH} characters. The rest part will be ended with ellipsis.") if
                !value.nil? && value.length > CHANGELOG_LENGTH
            end
          ),
          FastlaneCore::ConfigItem.new(
            key: :publish_type,
            description: "Should app be published after moderation",
            optional: true,
            default_value: Helper::PublishType::MANUAL,
            type: String,
            verify_block: proc do |value|
              UI.user_error!("Publish type must have one of the followed values: #{Helper.all_constants(Helper::PublishType).join(", ")}") unless
                value && Helper.has_constant?(Helper::PublishType, value)
            end
          ),
          FastlaneCore::ConfigItem.new(
            key: :publish_date_time,
            description: "The date time when app would be automatically released after moderation passed",
            optional: true,
            type: Time,
            verify_block: proc do |value|
              UI.user_error!("The specified time can't be older than now") unless
                value && value >= Time.now
            end
          ),
          FastlaneCore::ConfigItem.new(
            key: :app_type,
            description: "The app type: MAIN or GAMES",
            optional: true,
            type: String,
            verify_block: proc do |value|
              UI.user_error!("App type must have one of the followed values: #{Helper.all_constants(Helper::AppType).join(", ")}") unless
                value && Helper.has_constant?(Helper::AppType, value)
            end
          ),
          FastlaneCore::ConfigItem.new(
            key: :categories,
            description: "The app categories",
            optional: true,
            type: Array,
            verify_block: proc do |array|
              UI.user_error!("App categories array can't be empty") if array.empty?
              UI.important("Maximum count of app categories is #{APP_CATEGORIES_COUNT}") if array.length > APP_CATEGORIES_COUNT
            end
          ),
          FastlaneCore::ConfigItem.new(
            key: :apk_paths,
            env_name: "RUSTORE_APK_PATHS",
            description: "An array of paths to APK files and their metadata to upload",
            optional: true,
            type: Array,
            verify_block: proc do |array|
              UI.user_error!("APK packages array can't be empty") if array.empty?
            end
          ),
          FastlaneCore::ConfigItem.new(
            key: :aab_paths,
            env_name: "RUSTORE_AAB_PATHS",
            description: "An array of paths to AAB files and their metadata to upload",
            optional: true,
            type: Array,
            verify_block: proc do |array|
              UI.user_error!("AAB packages array can't be empty") if array.empty?
            end
          ),
          FastlaneCore::ConfigItem.new(
            key: :icon,
            env_name: "RUSTORE_ICON_PATH",
            description: "The path to an application icon",
            optional: true,
            type: String,
            verify_block: proc do |value|
              UI.user_error!("Icon validation failed. Check the errors above.") unless
                Helper::ImageValidator.validate_icon(File.expand_path(value))
            end
          ),
          FastlaneCore::ConfigItem.new(
            key: :screenshots,
            env_name: "RUSTORE_SCREENSHOTS_PATH",
            description: "An array of paths to screenshots to upload",
            optional: true,
            type: Array,
            verify_block: proc do |array|
              UI.user_error!("Screenshots array can't be empty") if array.empty?
              UI.important("Maximum count of screenshots is #{SCREENSHOTS_COUNT}") if array.length > SCREENSHOTS_COUNT

              counter = 0
              has_error = false

              array.each do |value|
                has_error &&= !Helper::ImageValidator.validate_screenshot(File.expand_path(value), counter)
                counter += 1
              end

              UI.user_error!("Screenshots validation failed. Check the errors above.") if has_error
            end
          ),
          FastlaneCore::ConfigItem.new(
            key: :remove_active_draft,
            description: "Automatically remove the last created draft",
            optional: true,
            default_value: false,
            type: Fastlane::Boolean
          ),
          FastlaneCore::ConfigItem.new(
            key: :timeout,
            env_name: "RUSTORE_PUSHING_TIMEOUT",
            description: "Request timeout in seconds applied to individual HTTP requests",
            optional: true,
            default_value: 600,
            type: Integer,
            verify_block: proc do |value|
              UI.important("Request timeout can't be less than or equal to zero. Using default value.") if
                value.zero? || value.negative?
            end
          )
        ]
      end

      def self.category
        :production
      end

      def self.create_draft(params)
        active_version = Helper::Uploader.get_active_version(params[:package_name], params[:timeout])

        if active_version != -1
          # remove active draft if needed
          if params.values.include?(:remove_active_draft) && [true].include?(params.values[:remove_active_draft])
            data = {
              package: params[:package_name],
              version: active_version
            }

            UI.message("Removing active draft with ID = #{active_version} ...")
            Helper::Uploader.remove_draft(data, params[:timeout])
            UI.success("The draft ID = #{active_version} has been removed")
          else
            UI.message("Use existing draft with ID = #{active_version}. Data fields would be ignored.")
            return
          end
        end

        data = {
          package: params[:package_name],
          publish_type: params.values[:publish_type]
        }

        data[:app_name] = params.values[:app_name] if
          !params.values[:app_name].nil? && !params.values[:app_name].empty?
        data[:short_description] = params.values[:short_description] if
          !params.values[:short_description].nil? && !params.values[:short_description].empty?
        data[:full_description] = params.values[:full_description] if
          !params.values[:full_description].nil? && !params.values[:full_description].empty?
        data[:changelog] = params.values[:changelog] if
          !params.values[:changelog].nil? && !params.values[:changelog].empty?
        data[:publish_date_time] = params.values[:publish_date_time] unless params.values[:publish_date_time].nil?

        UI.message("Creating a draft ...")
        version = Helper::Uploader.create_draft(data, params[:timeout])
        UI.success("A new draft has been created: #{version}")
      end

      def self.upload_apk(params, version)
        return unless params.values.include?(:apk_paths) && !params.values[:apk_paths].nil? &&
                      !params.values[:apk_paths].empty?

        UI.message("Process APK packages ...")

        has_aab = params.values.include?(:aab_paths) && !params.values[:aab_paths].nil? &&params.values[:aab_paths].length.positive?
        max_count = has_aab ? APK_PACKAGES_COUNT : APK_ONLY_PACKAGES_COUNT
        counter = 0

        params.values[:apk_paths].each do |apk|
          break if counter >= max_count

          data = {
            package: params[:package_name],
            version: version,
            file: File.expand_path(apk[:file]),
            services_type: apk.include?(:services_type) && apk[:services_type].is_a?(String) ? apk[:services_type] : Helper::ServicesType::UNKNOWN,
            is_main_apk: apk.include?(:is_main_apk) && [true, false].include?(apk[:is_main_apk]) ? apk[:is_main_apk] : false
          }

          UI.message("Uploading package with the following values:")
          UI.message("---------------------")

          data_str = JSON.pretty_generate(data)
          data_str.each_line do |x|
            UI.message(x.gsub("\n", ""))
          end

          UI.message("---------------------")
          Helper::Uploader.upload_package(data, false, params[:timeout])
          UI.success("Package has been uploaded successfully")

          counter += 1
        end
      end

      def self.upload_aab(params, version)
        return unless params.values.include?(:aab_paths) && !params.values[:aab_paths].nil? &&
                      !params.values[:aab_paths].empty?
        
        UI.message("Process AAB packages ...")

        counter = 0

        params.values[:apk_paths].each do |aab|
          break if counter >= AAB_PACKAGES_COUNT

          data = {
            package: params[:package_name],
            version: version,
            file: File.expand_path(aab[:file])
          }

          UI.message("Uploading package with the following values:")
          UI.message("---------------------")

          data_str = JSON.pretty_generate(data)
          data_str.each_line do |x|
            UI.message(x.gsub("\n", ""))
          end

          UI.message("---------------------")
          Helper::Uploader.upload_package(data, true, params[:timeout])
          UI.success("Package has been uploaded successfully")

          counter += 1
        end
      end

      def self.upload_icon(params, version)
        return unless params.values.include?(:icon) && !params.values[:icon].nil?

        data = {
          package: params[:package_name],
          version: version,
          file: File.expand_path(params[:icon])
        }

        UI.message("Uploading icon with the following values:")
        UI.message("---------------------")

        data_str = JSON.pretty_generate(data)
        data_str.each_line do |x|
          UI.message(x.gsub("\n", ""))
        end

        UI.message("---------------------")
        Helper::Uploader.upload_icon(data, params[:timeout])
        UI.success("The icon has been uploaded successfully")
      end

      def self.upload_screenshots(params, version)
        return unless params.values.include?(:screenshots) && !params.values[:screenshots].nil? &&
                      !params.values[:screenshots].empty?

        UI.message("Process screenshots ...")

        counter = 0
        params.values[:screenshots].each do |file|
          break if counter >= SCREENSHOTS_COUNT

          file = File.expand_path(file)
          data = {
            package: params[:package_name],
            version: version,
            file: file,
            orientation: Helper::ImageValidator.screenshot_orientation(file),
            ordinal: counter
          }

          UI.message("Uploading screenshot with the following values:")
          UI.message("---------------------")

          data_str = JSON.pretty_generate(data)
          data_str.each_line do |x|
            UI.message(x.gsub("\n", ""))
          end

          UI.message("---------------------")
          Helper::Uploader.upload_screenshot(data, params[:timeout])
          UI.success("The screenshot has been uploaded successfully")

          counter += 1
        end
      end

      def self.commit(params, version)
        data = {
          package: params[:package_name],
          version: version,
          priority_update: 0
        }

        UI.message("Committing the draft ...")
        Helper::Uploader.commit(data, params[:timeout])
        UI.success("Submission passed! Wait until moderation process ends")
      end

      def self.validate_packages_list(apk_paths, aab_paths)
        if apk_paths.length.positive? && aab_paths.length.positive?
          UI.important("Maximum count of packages is #{APK_PACKAGES_COUNT} for APK and #{AAB_PACKAGES_COUNT} for AAB") if
            apk_paths.length > APK_PACKAGES_COUNT || aab_paths.length > AAB_PACKAGES_COUNT
        elsif apk_paths.length.positive?
          UI.important("Maximum count of packages is #{APK_ONLY_PACKAGES_COUNT} for APK only") if
            apk_paths.length > APK_ONLY_PACKAGES_COUNT
        elsif aab_paths.length.positive?
          UI.important("Maximum count of packages is #{AAB_PACKAGES_COUNT} for AAB only") if
            aab_paths.length > AAB_PACKAGES_COUNT
        end

        counter = 0
        has_error = false

        array.each do |value|
          has_error &&= !validate_apk(value, counter)
          counter += 1
        end

        unless array.find_all { |x| x.include?(:is_main_apk) && x[:is_main_apk] == true }.empty?
          UI.error(`Only one package can be chosen as main`)
          has_error = true
        end

        UI.user_error!("Some APK settings contain errors. Check them above.") if has_error
      end

      def self.validate_apk(value, counter)
        has_error = false
        path = File.expand_path(value[:path])
        services_type = value[:services_type]

        unless value.include?(:is_main_apk)
          UI.error("[#{counter}] You must define is this APK file main or not")
          has_error = true
        end

        unless path && !path.empty?
          UI.error("[#{counter}] Path to the APK file is invalid: #{path}")
          has_error = true
        end

        unless File.exist?(path)
          UI.error("[#{counter}] There is no any file that provided in APK file path: #{path}")
          has_error = true
        end

        unless path.end_with?(".apk")
          UI.error("[#{counter}] Path to the APK file doesn't point to the file with .apk extension: #{path}")
          has_error = true
        end

        if !services_type.is_a?(String) || (!services_type.nil? && !services_type.empty? && !Helper.has_constant?(Helper::ServicesType, services_type))
          constants = Helper.all_constants(Helper::ServicesType)
          UI.error("[#{counter}] Incorrect services type for #{path}. Pick one from this array: #{constants.join(", ")}")
          has_error = true
        end

        !has_error
      end

      def self.validate_app_categories(params)
        return true if params.values[:categories].nil?

        has_error = false

        if params.values[:app_type].nil?
          UI.error("App type must be defined along with chosen categories")
        else
          app_category_module = params.values[:app_type] == Helper::AppType::MAIN ? Helper::AppCategory::Main : Helper::AppCategory::Games
          params.values[:categories].each do |x|
            UI.error("Unknown app category: #{x}") if Helper.has_constant?(app_category_module, x)
          end
        end

        !has_error
      end
    end
  end
end
