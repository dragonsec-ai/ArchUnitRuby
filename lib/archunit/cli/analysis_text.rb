# frozen_string_literal: true

module ArchUnit
  module CLI
    # Concise human diagnostics; nil remains unavailable, never zero.
    # @api private
    module AnalysisText
      def self.write(analysis, out)
        out.puts("Analysis: #{analysis[:status]}")
        analysis[:scopes].each { |scope| write_scope(scope, out) }
        analysis.fetch(:advisories, []).each do |hint|
          out.puts("  Advisory (#{hint[:rule_names].join(', ')}): #{hint[:message]}")
        end
        out.puts(analysis[:notice]) unless analysis[:scopes].empty?
      end

      def self.write_scope(scope, out)
        mode = scope[:dependency_analysis] || 'source metrics (dependency analysis unavailable)'
        out.puts("  Scope #{scope[:id]}: #{scope[:project_root]} — #{mode}; #{scope[:status]}")
        counts = scope[:counters].map do |name, value|
          "#{name}=#{value.nil? ? 'unavailable' : value}"
        end
        out.puts("    #{counts.join(', ')}; cache_hits=#{scope[:cache_hits]}")
      end
      private_class_method :write_scope
    end
  end
end
