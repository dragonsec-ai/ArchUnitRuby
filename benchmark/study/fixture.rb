# frozen_string_literal: true

require 'fileutils'
require 'pathname'

module PerformanceStudy
  # Generated Ruby production shapes with an independently known directed-edge oracle.
  class Fixture
    attr_reader :root, :pairs, :density, :shape

    def initialize(root:, pairs:, density:, shape:)
      unless pairs.is_a?(Integer) && pairs.between?(4, 1000) && [1, 3].include?(density)
        raise ArgumentError, 'study requires 4..1000 pairs and density 1 or 3'
      end
      raise ArgumentError, 'unknown study shape' unless %w[rails engines].include?(shape)

      @root = root
      @pairs = pairs
      @density = density
      @shape = shape
    end

    def prepare
      FileUtils.mkdir_p(root)
      File.write(File.join(root, 'Gemfile'), "raise 'do not evaluate target Gemfile'")
      pairs.times do |index|
        write_api(index)
        write(db(index), "module Db; class Store#{index}; end; end\nraise 'do not run target'")
      end
    end

    def api(index)
      "#{prefix(index)}/app/api/request_#{index}.rb".delete_prefix('/')
    end

    def db(index)
      "#{prefix(index)}/app/db/store_#{index}.rb".delete_prefix('/')
    end

    def oracle(extra: false)
      pairs.times.flat_map do |index|
        targets(index, extra: extra && index.zero?).map { |target| [api(index), db(target)] }
      end
    end

    def write_api(index, extra: false)
      dependencies = targets(index, extra:)
      imports = dependencies.map { |target| import(api(index), db(target)) }
      calls = dependencies.map { |target| "::Db::Store#{target}.new" }
      code = [*imports, "module Api; class Request#{index}; def call;", *calls,
              "end; end; end\nraise 'do not run target'"]
      write(api(index), code.join("\n"))
    end

    private

    def prefix(index)
      shape == 'engines' ? "engines/package_#{index % 4}" : ''
    end

    def targets(index, extra: false)
      (density + (extra ? 1 : 0)).times.map { |offset| (index + offset) % pairs }
    end

    def import(from, to)
      directory = Pathname.new(from).dirname
      relative = Pathname.new(to.delete_suffix('.rb')).relative_path_from(directory)
      "require_relative #{relative.to_s.tr('\\', '/').dump}"
    end

    def write(path, contents)
      full_path = File.join(root, path)
      FileUtils.mkdir_p(File.dirname(full_path))
      File.write(full_path, contents)
    end
  end
end
