module OrderMetricsSql
  module_function

  def gift_default_cost_rub
    value = ENV.fetch("GIFT_DEFAULT_COST_RUB", "60").to_f
    value.negative? ? 0.0 : value
  end

  def effective_cost_sql(order_alias = "o")
    gift_cost = format("%.2f", gift_default_cost_rub)
    <<~SQL.squish
      CASE
        WHEN #{order_alias}.cost_rub IS NOT NULL AND #{order_alias}.cost_rub > 0 THEN #{order_alias}.cost_rub
        WHEN COALESCE(NULLIF(#{order_alias}.product_type, ''), 'unknown') = 'gift' THEN #{gift_cost}
        ELSE COALESCE(#{order_alias}.cost_rub, 0)
      END
    SQL
  end

  def effective_profit_sql(order_alias = "o")
    <<~SQL.squish
      CASE
        WHEN #{order_alias}.profit_rub IS NOT NULL THEN #{order_alias}.profit_rub
        ELSE COALESCE(#{order_alias}.amount_rub, 0) - (#{effective_cost_sql(order_alias)})
      END
    SQL
  end
end
