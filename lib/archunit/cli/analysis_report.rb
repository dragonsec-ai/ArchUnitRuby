# frozen_string_literal: true

module ArchUnit
  module CLI
    # Groups observations by immutable analysis identity, never summing overlapping scopes.
    # @api private
    class AnalysisReport
      NOTICE = 'Counts describe bounded static analysis, not semantic coverage or proven missed ' \
               'dependencies. A passing policy is not proof of complete runtime architecture.'
      MESSAGES = {
        rails_no_scoped_imports: 'No cross-file imports found among the selected Rails files. ' \
                                 'Constant references were not checked. If these files rely on ' \
                                 'autoloading, try --dependency-analysis imports_and_constants.'
      }.freeze
      private_constant :MESSAGES

      def initialize
        @scopes = {}.compare_by_identity
        @rules = []
        @advisories = {}
      end

      def for_rule(name)
        previous = @current_rule
        @current_rule = name
        @rules << name unless @rules.include?(name)
        yield
      ensure
        @current_rule = previous
      end

      def observe(snapshot, cache_hit: false)
        scope = scope_for(snapshot)
        scope[:observations] += 1
        scope[:cache_hits] += 1 if cache_hit
        names = scope[:rule_names]
        names << @current_rule if @current_rule && !names.include?(@current_rule)
      end

      def for_name(name)
        scopes = @scopes.values.select { |scope| scope[:rule_names].include?(name) }
        { status: availability(scopes), scope_ids: scopes.map { |scope| scope[:id] } }
      end

      def advise(code)
        return unless @current_rule

        (@advisories[code] ||= Set.new).add(@current_rule)
      end

      def to_h
        scopes = @scopes.values.map { |scope| scope.merge(rule_names: scope[:rule_names].dup) }
        status = availability(scopes)
        if status == 'available' && @rules.any? { |name| for_name(name)[:status] != 'available' }
          status = 'partial'
        end
        result = { status:, scopes:, notice: NOTICE }
        result[:advisories] = advisory_entries unless @advisories.empty?
        result
      end

      private

      def advisory_entries
        @advisories.map do |code, names|
          { code: code.to_s, rule_names: names.to_a, message: MESSAGES.fetch(code) }
        end
      end

      def scope_for(snapshot)
        @scopes[snapshot] ||= snapshot.merge(
          id: @scopes.length + 1, observations: 0, cache_hits: 0, rule_names: []
        )
      end

      def availability(scopes)
        return 'unavailable' if scopes.empty?

        scopes.all? { |scope| scope[:status] == 'analyzed' } ? 'available' : 'partial'
      end
    end
  end
end
