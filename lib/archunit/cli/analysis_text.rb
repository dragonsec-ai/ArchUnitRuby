# frozen_string_literal: true

module ArchUnit
  module CLI
    # Concise human diagnostics; nil remains unavailable, never zero.
    # @api private
    module AnalysisText
      SOURCE_LABELS = {
        'source_calls' => 'source calls',
        'source_declarations' => 'source declarations',
        'source_metrics' => 'source metrics'
      }.freeze
      private_constant :SOURCE_LABELS

      def self.write(analysis, out)
        out.puts("Analysis: #{analysis[:status]}")
        analysis[:scopes].each { |scope| write_scope(scope, out) }
        analysis.fetch(:advisories, []).each do |hint|
          out.puts("  Advisory (#{hint[:rule_names].join(', ')}): #{hint[:message]}")
        end
        out.puts(analysis[:notice]) unless analysis[:scopes].empty?
      end

      def self.write_scope(scope, out)
        mode = scope[:dependency_analysis] || source_scope(scope)
        out.puts("  Scope #{scope[:id]}: #{scope[:project_root]} — #{mode}; #{scope[:status]}")
        counts = scope[:counters].map do |name, value|
          "#{name}=#{value.nil? ? 'unavailable' : value}"
        end
        out.puts("    #{counts.join(', ')}; cache_hits=#{scope[:cache_hits]}")
      end
      private_class_method :write_scope

      def self.source_scope(scope)
        name = SOURCE_LABELS.fetch(scope[:kind], 'source analysis')
        "#{name} (dependency analysis unavailable)"
      end
      private_class_method :source_scope
    end
  end
end
