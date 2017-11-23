require "./validations"
require "./needy_initializer"

abstract class LuckyRecord::Form(T)
  include LuckyRecord::Validations
  include LuckyRecord::NeedyInitializer
  include LuckyRecord::AllowVirtual

  macro inherited
    @valid : Bool = true
    @performed : Bool = false

    @@allowed_param_keys = [] of String
    @@schema_class = T
  end

  property? performed : Bool = false

  @record : T?
  @params : LuckyRecord::Paramable
  getter :record, :params

  abstract def table_name
  abstract def fields

  def form_name
    self.class.name.underscore.gsub("_form", "")
  end

  def errors
    fields.reduce({} of Symbol => Array(String)) do |errors_hash, field|
      if field.errors.empty?
        errors_hash
      else
        errors_hash[field.name] = field.errors
        errors_hash
      end
    end
  end

  macro add_fields(fields)
    private def extract_changes_from_params
      allowed_params.each do |key, value|
        {% for field in fields %}
          set_{{ field[:name] }}_from_param value if key == {{ field[:name].stringify }}
        {% end %}
      end
    end

    {% for field in fields %}
      @_{{ field[:name] }} : LuckyRecord::Field({{ field[:type] }}?)?

      def {{ field[:name] }}
        _{{ field[:name] }}
      end

      private def _{{ field[:name] }}
        @_{{ field[:name] }} ||= LuckyRecord::Field({{ field[:type] }}?).new(
          name: :{{ field[:name].id }},
          param: allowed_params["{{ field[:name] }}"]?,
          value: @record.try(&.{{ field[:name] }}),
          form_name: form_name)
      end

      def allowed_params
        new_params = {} of String => String
        @params.nested!(form_name).each do |key, value|
          new_params[key] = value
        end
        new_params.select(@@allowed_param_keys)
      end

      def set_{{ field[:name] }}_from_param(value)
        parse_result = {{ field[:type] }}::Lucky.parse(value)
        if parse_result.is_a? LuckyRecord::Type::SuccessfulCast
          {{ field[:name] }}.value = parse_result.value
        else
          {{ field[:name] }}.add_error "is invalid"
        end
      end
    {% end %}

    def fields
      database_fields + virtual_fields
    end

    private def database_fields
      [
        {% for field in fields %}
          {{ field[:name] }},
        {% end %}
      ]
    end

    def required_fields
      {
        {% for field in fields %}
          {% if !field[:nilable] && !field[:autogenerated] %}
            {{ field[:name] }},
          {% end %}
        {% end %}
      }
    end

    def after_prepare
      validate_required *required_fields
    end
  end

  private def named_tuple_to_params(named_tuple)
    params_with_stringified_keys = {} of String => String
    named_tuple.each do |key, value|
      params_with_stringified_keys[key.to_s] = value
    end
    LuckyRecord::Params.new params_with_stringified_keys
  end

  private def ensure_paramable(params)
    if params.is_a? LuckyRecord::Paramable
      params
    else
      LuckyRecord::Params.new(params)
    end
  end

  def valid? : Bool
    prepare
    after_prepare
    fields.all? &.valid?
  end

  abstract def after_prepare

  def save_succeeded?
    !save_failed?
  end

  def save_failed?
    !valid? && performed?
  end

  macro allow(*field_names)
    {% for field_name in field_names %}
      def {{ field_name.id }}
        LuckyRecord::AllowedField.new _{{ field_name.id }}
      end

      @@allowed_param_keys << "{{ field_name.id }}"
    {% end %}
  end

  def changes
    _changes = {} of Symbol => String?
    fields.each do |field|
      if field.changed?
        _changes[field.name] = field.value.to_s
      end
    end
    _changes
  end

  def save : Bool
    @performed = true

    if valid?
      before_save
      insert_or_update
      after_save(record.not_nil!)
      true
    else
      false
    end
  end

  def save! : T
    if save
      record.not_nil!
    else
      raise LuckyRecord::InvalidFormError.new(form_name: typeof(self).to_s, form_object: self)
    end
  end

  def update! : T
    save!
  end

  private def insert_or_update
    if record_id
      update record_id
    else
      insert
    end
  end

  private def record_id
    @record.try &.id
  end

  # Default callbacks
  def prepare; end
  def after_prepare; end
  def before_save; end
  def after_save(_record : T); end

  private def insert
    self.created_at.value = Time.now
    self.updated_at.value = Time.now
    @record = LuckyRecord::Repo.run do |db|
      db.query insert_sql.statement, insert_sql.args do |rs|
        @@schema_class.from_rs(rs)
      end.first
    end
  end

  private def update(id)
    @record = LuckyRecord::Repo.run do |db|
      db.query update_query(id).statement_for_update(changes), update_query(id).args_for_update(changes) do |rs|
        @@schema_class.from_rs(rs)
      end.first
    end
  end

  private def update_query(id)
    LuckyRecord::QueryBuilder
      .new(table_name)
      .where(LuckyRecord::Where::Equal.new(:id, id.to_s))
  end

  private def insert_sql
    LuckyRecord::Insert.new(table_name, changes)
  end
end
