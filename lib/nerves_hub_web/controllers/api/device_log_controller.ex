defmodule NervesHubWeb.API.DeviceLogController do
  @moduledoc """
  The log lines a device has sent over the logging extension.

  Read-only. Log lines arrive on the device's own connection and there is no
  way to write one here.

  Lines can be narrowed by level, by a window of time, and by a search term
  matched against the message text.

  Whether the logging extension is currently enabled for the product or the
  device governs whether new lines arrive, not whether stored ones can be read,
  so turning it off leaves everything collected before that still readable.
  A deployment with no analytics database configured has nothing to read from
  at all, and says so rather than answering with an empty list.

  Log lines are dropped three days after they were logged, so this only ever
  answers for the recent past.
  """

  use NervesHubWeb, :api_controller
  use OpenApiSpex.ControllerSpecs

  alias NervesHub.Devices.LogLines
  alias NervesHubWeb.API.HistoryParams

  security([%{"bearer_auth" => []}])
  tags(["Device Logs"])

  plug(:require_membership when action in [:index])

  # OpenAPI specs for :index can be found in DeviceLogControllerSpecs, which
  # documents the product-scoped and the short device URL separately.
  operation(:index, [])

  def index(%{assigns: %{device: device}} = conn, params) do
    with :ok <- analytics_enabled(),
         {:ok, opts} <- query_opts(params) do
      render(conn, :index, log_lines: LogLines.for_device(device, opts))
    end
  end

  defp analytics_enabled() do
    if Application.get_env(:nerves_hub, :analytics_enabled) do
      :ok
    else
      {:error, :analytics_not_enabled}
    end
  end

  defp query_opts(params) do
    with {:ok, levels} <- HistoryParams.list("level", params["level"]),
         {:ok, search} <- search(params["search"]),
         {:ok, window} <- HistoryParams.window(params) do
      {:ok, [levels: levels, search: search] ++ window}
    end
  end

  defp search(nil), do: {:ok, nil}

  defp search(search) when is_binary(search) do
    case String.trim(search) do
      "" -> {:ok, nil}
      trimmed -> {:ok, trimmed}
    end
  end

  defp search(search), do: {:error, {:invalid_query_param, "search must be a string, got #{inspect(search)}."}}
end
