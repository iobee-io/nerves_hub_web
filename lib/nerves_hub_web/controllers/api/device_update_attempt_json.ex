defmodule NervesHubWeb.API.DeviceUpdateAttemptJSON do
  @moduledoc false

  def index(%{attempts: attempts}) do
    %{data: for(attempt <- attempts, do: attempt(attempt))}
  end

  defp attempt(attempt) do
    %{
      timestamp: attempt.timestamp,
      status: attempt.status,
      reason: attempt.reason,
      source: firmware(attempt.source),
      target: firmware(attempt.target),
      deployment_group: attempt.deployment_group && attempt.deployment_group.name
    }
  end

  defp firmware(nil), do: nil
  defp firmware(firmware), do: Map.take(firmware, [:uuid, :version])
end
