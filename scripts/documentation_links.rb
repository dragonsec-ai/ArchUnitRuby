# frozen_string_literal: true

require 'cgi'
require 'pathname'
require 'uri'

# Offline fragment checks for the three hand-written documents, not external websites.
module ArchUnitDocumentationLinks
  HTML_PAGES = %w[index.html file.GUIDE.html file.API.html].freeze
  SOURCES = %w[README.md GUIDE.md API.md].freeze

  module_function

  def rendered_errors(page)
    content = page.read
    errors = content.scan(/\bhref=["']([^"']+)["']/).flatten.filter_map do |href|
      rendered_fragment_error(page, href)
    end
    errors << 'Unrendered Markdown heading' if content.match?(/^\#{2,6} /)
    errors
  end

  def rendered_fragment_error(page, href)
    return if external?(href) || !href.include?('#')

    path, fragment = CGI.unescapeHTML(href).split('#', 2)
    target = path.empty? ? page : page.dirname.join(URI::DEFAULT_PARSER.unescape(path))
    return unless HTML_PAGES.include?(target.basename.to_s) && target.file?

    missing_fragment(target, fragment, href)
  end

  def source_errors(root)
    SOURCES.flat_map do |name|
      file = root.join(name)
      file.read.scan(/\[[^\]]*\]\(([^)]+)\)/).flatten.filter_map do |href|
        source_fragment_error(file, href)
      end
    end
  end

  def source_fragment_error(file, href)
    return if external?(href) || !href.include?('#')

    path, fragment = href.split('#', 2)
    target = path.empty? ? file : file.dirname.join(path)
    return unless SOURCES.include?(target.basename.to_s)

    missing_fragment(target, fragment, href)
  end

  def missing_fragment(target, fragment, href)
    return "Missing document: #{href}" unless target.file?
    return if fragment.nil? || fragment.empty?

    anchors = target.read.scan(/\b(?:id|name)=["']([^"']+)["']/).flatten
    decoded = URI::DEFAULT_PARSER.unescape(fragment)
    "Missing document anchor: #{href}" unless anchors.include?(decoded)
  end

  def external?(href)
    href.start_with?('//') || href.match?(/\A[a-z][a-z0-9+.-]*:/i)
  end
end
