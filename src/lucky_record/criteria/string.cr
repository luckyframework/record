class LuckyRecord::StringType::Criteria(T, V) < LuckyRecord::Criteria(T, V)
  @upper = false
  @lower = false

  def like(value : String)
    rows.query.where(LuckyRecord::Where::Like.new(column, value))
    rows
  end

  def ilike(value : String)
    rows.query.where(LuckyRecord::Where::Ilike.new(column, value))
    rows
  end

  def upper
    @upper = true
    self
  end

  def lower
    @lower = true
    self
  end

  def column
    if @upper
      "UPPER(#{@column})"
    elsif @lower
      "LOWER(#{@column})"
    else
      @column
    end
  end
end
