# frozen_string_literal: true

module ArchUnit
  module Common
    module Extraction
      # A direct call as written in Ruby source, without inferred receiver type.
      CallSite = Data.define(:file, :name, :receiver, :safe_navigation, :line, :column)
    end
  end
end
