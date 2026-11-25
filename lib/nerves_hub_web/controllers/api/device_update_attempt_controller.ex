defmodule NervesHubWeb.API.DeviceUpdateAttemptController do
  @moduledoc """
  How a device's firmware update attempts ended: succeeded, failed, ignored,
  rescheduled, expired or abandoned (`NervesHub.Devices.UpdateHistory`).

  Read-only. Attempts can be narrowed by status and by a window of time, and
  page by time like the device's logs and metrics. A deployment with no
  analytics database has no history to read, and says so rather than
  answering with an empty list.
  """

  use NervesHubWeb, :api_controller
  use OpenApiSpex.ControllerSpecs

  alias NervesHub.Devices.UpdateHistory
  alias NervesHubWeb.API.HistoryParams

  security([%{"bearer_auth" => []}])
  tags(["Device Update Attempts"])

  plug(:require_membership when action in [:index])

  # OpenAPI specs for :index can be found in DeviceUpdateAttemptControllerSpecs,
  # which documents the product-scoped and the short device URL separately.
  operation(:index, [])

  def index(%{assigns: %{device: device}} = conn, params) do
    with :ok <- analytics_enabled(),
         {:ok, opts} <- query_opts(params) do
      render(conn, :index, attempts: UpdateHistory.attempts_for_device(device, opts))
    end
  end

  defp analytics_enabled() do
    if Application.get_env(:nerves_hub, :analytics_enabled) do
      :ok
    else
      {:error,
       {:analytics_not_enabled,
        "This platform has no analytics database configured, so device update history is not stored. " <>
          "Contact your Ops team for more information."}}
    end
  end

  defp query_opts(params) do
    with {:ok, statuses} <- HistoryParams.list("status", params["status"]),
         {:ok, window} <- HistoryParams.window(params) do
      {:ok, [statuses: statuses] ++ window}
    end
  end
end
