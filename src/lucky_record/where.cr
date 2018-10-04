module LuckyRecord::Where
  abstract class SqlClause
    getter :column

    def initialize(@column : Symbol | String)
    end

    abstract def operator : String
    abstract def negated : SqlClause

    def prepare
      "#{column} #{operator}"
    end
  end

  abstract class ComparativeSqlClause < SqlClause
    getter :value

    def initialize(@column : Symbol | String, @value : String | Array(String) | Array(Int32))
    end

    abstract def operator : String
    abstract def negated : ComparativeSqlClause

    def prepare(prepared_statement_placeholder : String)
      "#{column} #{operator} #{prepared_statement_placeholder}"
    end
  end

  class Null < SqlClause
    def operator
      "IS NULL"
    end

    def negated : NotNull
      NotNull.new(@column)
    end
  end

  class NotNull < SqlClause
    def operator
      "IS NOT NULL"
    end

    def negated : Null
      Null.new(@column)
    end
  end

  class Equal < ComparativeSqlClause
    def operator
      "="
    end

    def negated : NotEqual
      NotEqual.new(@column, @value)
    end
  end

  class NotEqual < ComparativeSqlClause
    def operator
      "!="
    end

    def negated : Equal
      Equal.new(@column, @value)
    end
  end

  class GreaterThan < ComparativeSqlClause
    def operator
      ">"
    end

    def negated : LessThanOrEqualTo
      LessThanOrEqualTo.new(@column, @value)
    end
  end

  class GreaterThanOrEqualTo < ComparativeSqlClause
    def operator
      ">="
    end

    def negated : LessThan
      LessThan.new(@column, @value)
    end
  end

  class LessThan < ComparativeSqlClause
    def operator
      "<"
    end

    def negated : GreaterThanOrEqualTo
      GreaterThanOrEqualTo.new(@column, @value)
    end
  end

  class LessThanOrEqualTo < ComparativeSqlClause
    def operator
      "<="
    end

    def negated : GreaterThan
      GreaterThan.new(@column, @value)
    end
  end

  class Like < ComparativeSqlClause
    def operator
      "LIKE"
    end

    def negated : NotLike
      NotLike.new(@column, @value)
    end
  end

  class Ilike < ComparativeSqlClause
    def operator
      "ILIKE"
    end

    def negated : NotIlike
      NotIlike.new(@column, @value)
    end
  end

  class NotLike < ComparativeSqlClause
    def operator
      "NOT LIKE"
    end

    def negated : Like
      Like.new(@column, @value)
    end
  end

  class NotIlike < ComparativeSqlClause
    def operator
      "NOT ILIKE"
    end

    def negated : Ilike
      Ilike.new(@column, @value)
    end
  end

  class In < ComparativeSqlClause
    def operator
      "= ANY"
    end

    def negated : NotIn
      NotIn.new(@column, @value)
    end

    def prepare(prepared_statement_placeholder : String)
      "#{column} #{operator} (#{prepared_statement_placeholder})"
    end
  end

  class NotIn < ComparativeSqlClause
    def operator
      "!= ALL"
    end

    def negated : In
      In.new(@column, @value)
    end

    def prepare(prepared_statement_placeholder : String)
      "#{column} #{operator} (#{prepared_statement_placeholder})"
    end
  end

  class Raw
    @clause : String

    def initialize(statement : String, *bind_vars)
      ensure_enough_bind_variables_for!(statement, *bind_vars)
      @clause = build_clause(statement, *bind_vars)
    end

    def to_sql
      @clause
    end

    private def ensure_enough_bind_variables_for!(statement, *bind_vars)
      bindings = statement.chars.select(&.== '?')
      if bindings.size != bind_vars.size
        raise "wrong number of bind variables (#{bind_vars.size} for #{bindings.size}) in #{statement}"
      end
    end

    private def build_clause(statement, *bind_vars)
      bind_vars.each do |arg|
        if arg.is_a?(String) || arg.is_a?(Slice(UInt8))
          escaped = PG::EscapeHelper.escape_literal(arg)
        else
          escaped = arg
        end
        statement = statement.sub('?', escaped)
      end
      statement
    end
  end
end
