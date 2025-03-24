require "image_size"

module Fastlane
  module Helper
    class ImageValidator
      IMAGE_TYPES = %w[jpg jpeg png].freeze
      SCREENSHOT_MIN_DIM_SIZE = 320
      SCREENSHOT_MAX_DIM_SIZE = 3840
      SCREENSHOT_DIM_RATIO = 16 / 9
      ICON_DIM_SIZE = 512

      def self.mime_type(path)
        format = ImageSize.path(path).format

        case format
        when :png
          "image/png"
        when :jpg, :jpeg
          "image/jpeg"
        else
          UI.important("Can't determine image MIME type by file extension")
          "application/octet-stream"
        end
      end

      def self.screenshot_orientation(path)
        Helper::ScreenshotOrientation::PORTRAIT

        # TODO: PORTRAIT isn't supported by service
        # image = ImageSize.path(path)
        # image.width >= image.height ? Helper::ScreenshotOrientation::LANDSCAPE : Helper::ScreenshotOrientation::PORTRAIT
      end

      def self.validate_icon(path)
        return false unless check_path(path)

        has_error = false
        image = ImageSize.path(path)
        has_error &&= check_format(image)

        # TODO: less than 512 or strictly equals to?
        # https://help.rustore.ru/rustore/for_developers/work_with_RuStore_API/publish_RuStore_API/app_icon_loading
        if image.width != ICON_DIM_SIZE || image.height != ICON_DIM_SIZE
          UI.error(build_message("Icon size must be equal to 512x512px"))
          has_error = true
        end

        !has_error
      end

      def self.validate_screenshot(path, str_prefix)
        return false unless check_path(path, str_prefix)

        has_error = false
        image = ImageSize.path(path)
        has_error &&= check_format(image, str_prefix)

        if image.width < SCREENSHOT_MIN_DIM_SIZE || image.height < SCREENSHOT_MIN_DIM_SIZE
          UI.error(build_message("One side of the image is less than #{SCREENSHOT_MIN_DIM_SIZE}px", str_prefix))
          has_error = true
        end

        if image.width > SCREENSHOT_MAX_DIM_SIZE || image.height > SCREENSHOT_MAX_DIM_SIZE
          UI.error(build_message("One side of the image is greater than #{SCREENSHOT_MAX_DIM_SIZE}px", str_prefix))
          has_error = true
        end

        if image.width / image.height != SCREENSHOT_DIM_RATIO && image.height / image.width != SCREENSHOT_DIM_RATIO
          UI.error(build_message("Image dimensions ratio must be equal to 16:9 or 9:16", str_prefix))
          has_error = true
        end

        !has_error
      end

      def self.check_path(path, str_prefix = "")
        unless path && !path.empty?
          UI.error(build_message("Path to the image is invalid: #{path}", str_prefix))
          return false
        end

        unless File.exist?(path)
          UI.error(build_message("There is no any file that provided in image path: #{path}", str_prefix))
          return false
        end

        true
      end

      def self.check_format(image, str_prefix = "")
        passed_image_type = IMAGE_TYPES.find_all { |x| image.format == x }

        if passed_image_type.nil? || passed_image_type.empty?
          UI.error(build_message("Incorrect image type. Pick one from this array: #{IMAGE_TYPES.join(", ")}", str_prefix))
          return false
        end

        true
      end

      def self.build_message(message, prefix = "")
        !prefix.nil? && !prefix.empty? ? "[#{prefix}] #{message}" : message
      end

      public_class_method(:validate_icon)
      public_class_method(:validate_screenshot)
      public_class_method(:mime_type)
      public_class_method(:screenshot_orientation)

      private_class_method(:check_path)
      private_class_method(:check_format)
      private_class_method(:build_message)

      private_constant(:IMAGE_TYPES)
      private_constant(:SCREENSHOT_MIN_DIM_SIZE)
      private_constant(:SCREENSHOT_MAX_DIM_SIZE)
      private_constant(:SCREENSHOT_DIM_RATIO)
      private_constant(:ICON_DIM_SIZE)
    end
  end
end
