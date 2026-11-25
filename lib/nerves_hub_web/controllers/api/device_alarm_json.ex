defmodule NervesHubWeb.API.DeviceAlarmJSON do
  @moduledoc false

  def index(%{transitions: transitions}) do
    %{data: for(transition <- transitions, do: Map.take(transition, [:timestamp, :alarm, :event, :description]))}
  end
end
