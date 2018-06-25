require "db"
require "levenshtein"
require "./schema_enforcer"

class LuckyRecord::Model
  include LuckyRecord::Associations
  include LuckyRecord::SchemaEnforcer

  macro inherited
    FIELDS = [] of {name: Symbol, type: Object, nilable: Bool, autogenerated: Bool}
    ASSOCIATIONS = [] of {name: Symbol, foreign_key: Symbol, type: Object}
  end

  macro setup_autogenerated_columns(primary_key_type)
    {% if primary_key_type == :uuid %}
      column id : String, autogenerated: true
    {% else %}
      column id : Int32, autogenerated: true
    {% end %}

    column created_at : Time, autogenerated: true
    column updated_at : Time, autogenerated: true
  end

  def_equals @id

  def to_param
    id.to_s
  end

  macro table(table_name, primary_key_type = :bigint)
    setup_autogenerated_columns({{primary_key_type}})
    {{yield}}
    setup({{table_name}}, {{primary_key_type}})
  end

  def delete
    LuckyRecord::Repo.run do |db|
      db.exec "DELETE FROM #{@@table_name} WHERE id = #{id}"
    end
  end

  macro setup(table_name, primary_key_type)
    {% table_name = table_name.id %}
    setup_initialize
    setup_db_mapping
    setup_getters
    setup_base_query_class({{table_name}})
    setup_base_form_class({{table_name}})
    setup_table_name({{table_name}})
    setup_fields_method
    add_schema_enforcer_methods_for({{table_name}}, {{ FIELDS }})
  end

  macro setup_table_name(table_name)
    @@table_name = :{{table_name}}
    TABLE_NAME = :{{table_name}}
  end

  macro setup_initialize
    def initialize(
        {% for field in FIELDS %}
          @{{field[:name]}},
        {% end %}
      )
    end
  end

  # Setup [database mapping](http://crystal-lang.github.io/crystal-db/api/0.5.0/DB.html#mapping%28properties%2Cstrict%3Dtrue%29-macro) for the model's fields.
  #
  # NOTE: LuckyMigrator saves `Float` columns as numeric which need to be
  # converted from [PG::Numeric](https://github.com/will/crystal-pg/blob/master/src/pg/numeric.cr) back to `Float64` using a `convertor`
  # class.
  macro setup_db_mapping
    DB.mapping({
      {% for field in FIELDS %}
        {{field[:name]}}: {
          {% if field[:type] == Float64.id %}
            type: PG::Numeric,
            convertor: Float64Convertor,
          {% else %}
            type: {{field[:type]}}::Lucky::ColumnType,
          {% end %}
          nilable: {{field[:nilable]}},
        },
      {% end %}
    })
  end

  module Float64Converter
    def self.from_rs(rs)
      rs.read(PG::Numeric).to_f
    end
  end

  macro setup_base_query_class(table_name)
    LuckyRecord::BaseQueryTemplate.setup({{ @type }}, {{ FIELDS }}, {{ ASSOCIATIONS }}, {{ table_name }})
  end

  macro setup_base_form_class(table_name)
    LuckyRecord::BaseFormTemplate.setup({{ @type }}, {{ FIELDS }}, {{ table_name }})
  end

  macro setup_getters
    {% for field in FIELDS %}
      def {{field[:name]}}
        {{ field[:type] }}::Lucky.from_db! @{{field[:name]}}
      end
    {% end %}
  end

  macro column(type_declaration, autogenerated = false)
    {% if type_declaration.type.is_a?(Union) %}
      {% data_type = "#{type_declaration.type.types.first}".id %}
      {% nilable = true %}
    {% else %}
      {% data_type = "#{type_declaration.type}".id %}
      {% nilable = false %}
    {% end %}
    {% FIELDS << {name: type_declaration.var, type: data_type, nilable: nilable.id, autogenerated: autogenerated} %}
  end

  macro setup_fields_method
    def self.column_names : Array(Symbol)
      [
        {% for field in FIELDS %}
          :{{field[:name]}},
        {% end %}
      ]
    end
  end

  macro association(table_name, type, foreign_key = nil)
    {% ASSOCIATIONS << {type: type, name: table_name.id, foreign_key: foreign_key} %}
  end
end
