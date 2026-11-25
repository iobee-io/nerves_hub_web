defmodule NervesHubWeb.API.DeviceMetricController do
  @moduledoc """
  The metric history a device has reported, over the `health` or `metrics`
  extension.

  Read-only. Readings arrive on the device's own connection and there is no way
  to write one here.

  Answers in reports, the shape the device sent them in: one timestamp and the
  readings taken at it. A report can be narrowed to some of its metrics, and
  the history to a window of time.

  History is kept in the analytics database for thirty days. A deployment with
  no analytics database has no history to read, and says so rather than
  answering with an empty list.
  """

  use NervesHubWeb, :api_controller
  use OpenApiSpex.ControllerSpecs

  alias NervesHub.Devices.Metrics
  alias NervesHubWeb.API.HistoryParams

  security([%{"bearer_auth" => []}])
  tags(["Device Metrics"])

  plug(:require_membership when action in [:index])

  # OpenAPI specs for :index can be found in DeviceMetricControllerSpecs, which
  # documents the product-scoped and the short device URL separately.
  operation(:index, [])

  def index(%{assigns: %{device: device}} = conn, params) do
    with :ok <- analytics_enabled(),
         {:ok, opts} <- query_opts(params) do
      render(conn, :index, reports: Metrics.reports_for_device(device, opts))
    end
  end

  defp analytics_enabled() do
    if Application.get_env(:nerves_hub, :analytics_enabled) do
      :ok
    else
      {:error,
       {:analytics_not_enabled,
        "This platform has no analytics database configured, so device metric history is not stored. " <>
          "Contact your Ops team for more information."}}
    end
  end

  # Metric names are the device's own, so nothing here is checked against a
  # list — a name no device has reported is a filter that matches nothing
  # rather than an error.
  defp query_opts(params) do
    with {:ok, keys} <- HistoryParams.list("key", params["key"]),
         {:ok, window} <- HistoryParams.window(params) do
      {:ok, [keys: keys] ++ window}
    end
  end
end
