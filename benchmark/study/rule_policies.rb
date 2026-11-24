# frozen_string_literal: true

module PerformanceStudy
  # Twenty distinct, nonempty policies over the existing four-engine fixture.
  module RulePolicies
    module_function

    def boundary(root)
      ArchUnit.files(root).in_path('**/app/api/**').should.depend_on_files
              .in_path('**/app/db/**')
    end

    def build(root, workload)
      case workload
      when 'one' then [boundary(root)]
      when 'identical' then Array.new(20, boundary(root))
      when 'varied' then file_rules(root) + layer_rules(root) + slice_rules(root)
      else raise ArgumentError, 'workload must be graph, one, identical or varied'
      end
    end

    def file_rules(root)
      api = ArchUnit.files(root).in_path('**/app/api/**')
      db = ArchUnit.files(root).in_path('**/app/db/**')
      [boundary(root), api.should_not.depend_on_files.in_path('**/app/api/**'),
       db.should_not.depend_on_files.in_path('**/app/api/**'),
       *naming_rules(root, api, db), ArchUnit.files(root).should.have_no_cycles]
    end

    def naming_rules(root, api, db)
      [ArchUnit.files(root).should.have_name('*.rb'), api.should.have_name('request_*.rb'),
       db.should.have_name('store_*.rb')]
    end

    def layer_rules(root)
      engines = 4.times.map do |index|
        layers(root, "engines/package_#{index}/app/api/**")
          .where_layer('API').may_only_depend_on_layers('DB')
      end
      base = layers(root, '**/app/api/**')
      engines + [base.where_layer('API').may_only_depend_on_layers('DB'),
                 base.where_layer('DB').may_not_depend_on_layers('API'),
                 base.where_layer('API').may_not_depend_on_layers('API')]
    end

    def layers(root, api)
      ArchUnit.layers(root).layer('API').defined_by(api)
              .layer('DB').defined_by('**/app/db/**')
    end

    def slice_rules(root)
      scope = ArchUnit.project_slices(root).defined_by('engines/(**)/')
      [[0, 1], [0, 2], [0, 3], [1, 0], [1, 2], [1, 3]].map do |source, target|
        scope.should_not.contain_dependency("package_#{source}", "package_#{target}")
      end
    end

    def validate_controls(fixture, options)
      validate_forbidden(fixture, options)
      empty = ArchUnit.files(fixture.root).in_path('missing/**').should.have_no_cycles
                      .check(options)
      return if empty.one? && empty.first.is_a?(ArchUnit::EmptyTestViolation)

      raise 'empty selector silently passed'
    end

    def validate_forbidden(fixture, options)
      forbidden = ArchUnit.files(fixture.root).in_path('**/app/api/**').should_not
                          .depend_on_files.in_path('**/app/db/**').check(options)
      actual = forbidden.map do |violation|
        [violation.dependency.source_label, violation.dependency.target_label]
      end
      raise 'forbidden-dependency oracle changed' unless actual.sort == fixture.oracle.sort
    end
  end
end
