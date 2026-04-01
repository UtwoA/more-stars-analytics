class DashboardController < ApplicationController
  def overview
    render_panel_page("index.html")
  end

  def revenue
    render_panel_page("revenue.html")
  end

  def users
    render_panel_page("users.html")
  end

  def payments
    render_panel_page("payments.html")
  end

  def ops
    render_panel_page("ops.html")
  end

  private

  def render_panel_page(file_name)
    send_file Rails.root.join("public", "panel", file_name), type: "text/html", disposition: "inline"
  end
end
