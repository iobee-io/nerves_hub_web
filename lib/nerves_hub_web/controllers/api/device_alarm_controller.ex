defmodule NervesHubWeb.API.DeviceAlarmController do
  @moduledoc """
  The alarm history of a device: every raise and every resolve it reported.

  Read-only. Alarms arrive on the device's own connection. The device page
  shows what is alarming now; this answers what has alarmed, which is what a
  rollout check asks of the devices that took a release.

  Transitions can be narrowed by alarm name, by event (`raised` or
  `resolved`), and by a window of time. A deployment with no analytics
  database has no history to read, and says so rather than answering with an
  empty list.
  """

  use NervesHubWeb, :api_controller
  use OpenApiSpex.ControllerSpecs

  alias NervesHub.Devices.Alarms
  alias NervesHubWeb.API.HistoryParams

  security([%{"bearer_auth" => []}])
  tags(["Device Alarms"])

  plug(:require_membership when action in [:index])

  # OpenAPI specs for :index can be found in DeviceAlarmControllerSpecs, which
  # documents the product-scoped and the short device URL separately.
  operation(:index, [])

  def index(%{assigns: %{device: device}} = conn, params) do
    with :ok <- analytics_enabled(),
         {:ok, opts} <- query_opts(params) do
      render(conn, :index, transitions: Alarms.history_for_device(device, opts))
    end
  end

  defp analytics_enabled() do
    if Application.get_env(:nerves_hub, :analytics_enabled) do
      :ok
    else
      {:error,
       {:analytics_not_enabled,
        "This platform has no analytics database configured, so device alarm history is not stored. " <>
          "Contact your Ops team for more information."}}
    end
  end

  defp query_opts(params) do
    with {:ok, alarms} <- HistoryParams.list("alarm", params["alarm"]),
         {:ok, events} <- HistoryParams.list("event", params["event"]),
         {:ok, window} <- HistoryParams.window(params) do
      {:ok, [alarms: alarms, events: events] ++ window}
    end
  end
end
