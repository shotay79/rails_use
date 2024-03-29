require 'colorize'

require_relative 'configuration'

module RailsUse
  module Railsserializer2schema
    class << self
      def execute
        if RailsUse.configuration.schema_output_dir.blank?
          raise 'Please set RailsUse.configuration.schema_output_dir'
        end

        dir = RailsUse.configuration.schema_output_dir

        FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
        serializers_path = Dir.glob('app/serializers/**/*.rb')
        models = <<~TS
        TS
        serializers_path.each do |serializer_path|
          file_name = File.basename(serializer_path, '.rb')
          serializer_class = file_name.camelize.constantize
          interface = serializer_to_interface(serializer_class)

          models += interface
        end

        File.write(dir + '/index.ts', <<~TS
          #{models}
        TS
        )
        puts "f #{dir}".green
      end

      private

      def serializer_to_interface(serializer)
        dir = RailsUse.configuration.schema_output_dir
        serializer_attributes = serializer._attributes
        model_name = serializer.name.gsub('Serializer', '')
        camelcase_model_name = model_name.singularize.camelize(:lower)
        filename = dir + "/#{camelcase_model_name}.ts"
        file = File.exist?(filename) ? File.open(filename).read : ''

        begin
          model_class = model_name.constantize
        rescue NameError => _e
          return ''
        end
        columns = model_class.columns_hash
        schema_name = model_name.singularize.camelize(:lower) + 'Schema'
        interface_types = serializer_attributes.map do |attribute|
          column = columns[attribute.to_s]
          matched = file.match(/(#{attribute.to_s.camelize(:lower)}):\s(.+),/)
          if matched
            next { attribute.to_s.camelize(:lower) => matched[2] }
          end
          type = if column.nil?
                   'z.unknown()'
                 else
                   _type = "z" + type_to_interface_type(column.type)
                   if column.null
                     _type += '.nullable()'
                   end
                   _type
                 end
          { attribute.to_s.camelize(:lower) => type }
        end

        import_files = <<~TS
        TS

        relation_types = serializer._reflections.map do |association|
          relation_name = association[0].to_s
          pluralize_name = relation_name.pluralize.camelize(:lower)
          singularize_name = relation_name.singularize.camelize(:lower)
          matched = file.match(/(#{singularize_name}):\s(.+),/)
          if association[1].is_a?(ActiveModel::Serializer::BelongsToReflection)
            if model_class.reflect_on_association(relation_name).options[:polymorphic]
              if matched
                next { "#{singularize_name}" => matched[2] }
              end
              next { "#{singularize_name}" => "z.unknown()" }
            else
              import_files += <<~TS
                import { #{singularize_name}Schema } from './#{singularize_name}';
              TS
              if matched
                next { "#{singularize_name}" => matched[2] }
              end
              next { "#{singularize_name}" => "#{singularize_name}Schema.optional()" }
            end
          end

          if association[1].is_a?(ActiveModel::Serializer::HasManyReflection)
            import_files += <<~TS
              import { #{singularize_name}Schema } from './#{singularize_name}';
            TS
            next { "#{pluralize_name}" => "z.array(#{singularize_name}Schema).optional()" }
          end

          if association[1].is_a?(ActiveModel::Serializer::HasOneReflection)
            import_files += <<~TS
              import { #{singularize_name}Schema } from './#{singularize_name}';
            TS
            next { "#{singularize_name}" => "#{singularize_name}Schema.optional()" }
          end
        end

        File.write(dir + "/#{camelcase_model_name}.ts", <<~TS
          import { z } from "zod";
          #{import_files}
          export const #{schema_name} = z.object({
            #{
              [interface_types, relation_types].flatten.map do |type|
                type.keys[0] + ': ' + type.values[0] + ','
              end.join("\n\t")
            }
          })

          export type #{model_name} = z.infer<typeof #{schema_name}>;
        TS
        )
        <<~TS
          export * from './#{camelcase_model_name}';
        TS
      end

      def type_to_interface_type(type)
        case type
        when :uuid, :datetime, :date, :text
          '.string()'
        when :integer
          '.number()'
        else
          ".#{type}()"
        end
      end
    end
  end
end
