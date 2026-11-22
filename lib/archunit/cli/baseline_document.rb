# frozen_string_literal: true

require 'json'
require 'tempfile'
require_relative 'baseline_schema'
require_relative 'baseline_object'

module ArchUnit
  module CLI
    # Strict, bounded JSON input and explicit, atomic accepted-debt output.
    # @api private
    module BaselineDocument
      MAX_BYTES = 2_000_000
      private_constant :MAX_BYTES

      def self.load(path)
        validate_regular_file(path)
        bytes = File.open(path, 'rb') { |file| file.read(MAX_BYTES + 1) }
        raise ArgumentError, 'baseline exceeds 2 MB' if bytes.bytesize > MAX_BYTES

        document = JSON.parse(bytes, max_nesting: 32, object_class: BaselineObject)
        BaselineSchema.validate(document)
      rescue JSON::ParserError => e
        raise ArgumentError, "invalid baseline JSON: #{e.message}"
      end

      def self.write(path, entries, force: false)
        document = { 'schema_version' => 1, 'fingerprint_version' => 1, 'entries' => entries }
        json = "#{JSON.pretty_generate(document)}\n"
        BaselineSchema.validate(JSON.parse(json))
        raise ArgumentError, 'baseline exceeds 2 MB' if json.bytesize > MAX_BYTES

        atomic_write(path, json, force:)
      end

      def self.atomic_write(path, json, force:)
        Tempfile.create(['.archunit-baseline-', '.json'], File.dirname(path)) do |file|
          file.write(json)
          file.close
          force ? replace(file.path, path) : File.link(file.path, path)
        end
      end

      def self.replace(temporary, path)
        validate_regular_file(path) if File.exist?(path) || File.symlink?(path)
        File.rename(temporary, path)
      end

      def self.validate_regular_file(path)
        stat = File.lstat(path)
        return if stat.file? && !stat.symlink?

        raise ArgumentError, 'baseline must be a regular file, not a symlink or directory'
      end
      private_class_method :atomic_write, :replace, :validate_regular_file
    end
  end
end
