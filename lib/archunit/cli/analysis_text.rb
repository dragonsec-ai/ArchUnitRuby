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
        out.puts(scope_heading(scope, mode))
        counts = scope[:counters].map do |name, value|
          "#{name}=#{value.nil? ? 'unavailable' : value}"
        end
        out.puts("    #{counts.join(', ')}; cache_hits=#{scope[:cache_hits]}")
      end
      private_class_method :write_scope

      def self.scope_heading(scope, mode)
        if scope[:kind] == 'source_declarations'
          mode = 'source declarations (dependency analysis unavailable)'
        end
        "  Scope #{scope[:id]}: #{scope[:project_root]} — #{mode}; #{scope[:status]}"
      end
      private_class_method :scope_heading
    end
  end
end
