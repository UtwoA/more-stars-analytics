module Ops
  class JobsController < ApplicationController
    def index
      scope = AnalyticsJobRun.order(created_at: :desc)
      scope = scope.where(job_name: params[:job_name]) if params[:job_name].present?
      scope = scope.where(status: params[:status]) if params[:status].present?
      scope = scope.limit((params[:limit] || 200).to_i.clamp(1, 1000))

      render json: {
        items: scope.as_json,
        summary: {
          running: AnalyticsJobRun.where(status: "running").count,
          failed_last_24h: AnalyticsJobRun.where(status: "failed").where("created_at >= ?", 24.hours.ago).count,
          success_last_24h: AnalyticsJobRun.where(status: "success").where("created_at >= ?", 24.hours.ago).count
        }
      }
    end
  end
end

