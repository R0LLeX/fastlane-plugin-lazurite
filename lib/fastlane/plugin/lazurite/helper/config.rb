require "time"

module Fastlane
  module Helper
    class Config
      attr_accessor :key_id
      attr_accessor :private_key
    end

    class AuthData
      attr_accessor :token
      attr_accessor :created_at
      attr_accessor :time

      def valid?
        current_time = Time.now.to_i
        token? && current_time < (@created_at + @time)
      end

      def token?
        @token.is_a?(String) && !@token.nil? && !@token.empty?
      end

      def setup(token, time)
        @token = token
        @created_at = Time.now.to_i
        @time = time
      end
    end

    class << self
      attr_accessor :config
      attr_accessor :auth_data
    end

    self.config = Config.new
    self.auth_data = AuthData.new
    self.auth_data.setup("", 0)
  end
end
