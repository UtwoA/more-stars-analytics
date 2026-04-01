require "yaml"

ORDER_STATUSES = YAML.safe_load(
  File.read(Rails.root.join("config/order_statuses.yml"))
).freeze
