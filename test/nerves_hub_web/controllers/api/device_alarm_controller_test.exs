defmodule NervesHubWeb.API.DeviceAlarmControllerTest do
  # Not async: these tests read and write the AnalyticsRepo (ClickHouse), which
  # has no sandbox, and one of them toggles the global :analytics_enabled.
  use NervesHubWeb.APIConnCase, async: false

  alias NervesHub.Analytics.Buffer
  alias NervesHub.AnalyticsRepo
  alias NervesHub.DeviceLink.DeviceInfo
  alias NervesHub.Devices
  alias NervesHub.Devices.Alarms
  alias NervesHub.Devices.DeviceAlarmHistory

  setup %{product: product} do
    {:ok, device} = Devices.create_device(product, %{identifier: "device-1234"})
    {:ok, other} = Devices.create_device(product, %{identifier: "device-5678"})

    :ok = Buffer.flush(DeviceAlarmHistory)
    AnalyticsRepo.query!("TRUNCATE TABLE device_alarm_history")

    on_exit(fn ->
      :ok = Buffer.flush(DeviceAlarmHistory)
      AnalyticsRepo.query!("TRUNCATE TABLE device_alarm_history")
    end)

    [device: device, other: other, now: DateTime.utc_now()]
  end

  defp path(conn, org, product, device, params \\ []) do
    Routes.api_device_alarm_path(conn, :index, org.name, product.name, device.identifier, params)
  end

  defp info(device) do
    %DeviceInfo{
      device_id: device.id,
      device_identifier: device.identifier,
      org_id: device.org_id,
      product_id: device.product_id
    }
  end

  defp raise_alarm(device, alarm, description, at) do
    :ok = Alarms.raise_alarm(info(device), alarm, description, at)
    :ok = Buffer.flush(DeviceAlarmHistory)
  end

  defp clear_alarm(device, alarm, at) do
    :ok = Alarms.clear_alarm(info(device), alarm, at)
    :ok = Buffer.flush(DeviceAlarmHistory)
  end

  defp events(response), do: Enum.map(response["data"], &{&1["alarm"], &1["event"]})

  describe "index" do
    test "is empty for a device that never alarmed", %{conn: conn, org: org, product: product, device: device} do
      conn = get(conn, path(conn, org, product, device))

      assert json_response(conn, 200) == %{"data" => []}
    end

    test "returns raises and resolves newest first, with the description", %{
      conn: conn,
      org: org,
      product: product,
      device: device,
      now: now
    } do
      raise_alarm(device, "LowMemory", "largest free block 24576 bytes", DateTime.add(now, -120))
      clear_alarm(device, "LowMemory", DateTime.add(now, -60))

      response = json_response(get(conn, path(conn, org, product, device)), 200)

      assert events(response) == [{"LowMemory", "resolved"}, {"LowMemory", "raised"}]

      assert [%{"description" => nil}, %{"description" => "largest free block 24576 bytes", "timestamp" => _}] =
               response["data"]
    end

    test "does not return another device's alarms", %{
      conn: conn,
      org: org,
      product: product,
      device: device,
      other: other,
      now: now
    } do
      raise_alarm(other, "LowMemory", "theirs", now)

      assert json_response(get(conn, path(conn, org, product, device)), 200) == %{"data" => []}
    end

    test "is reachable on the short device URL", %{conn: conn, device: device, now: now} do
      raise_alarm(device, "LowMemory", "low", now)

      conn = get(conn, Routes.api_device_alarm_path(conn, :index, device.identifier))

      assert events(json_response(conn, 200)) == [{"LowMemory", "raised"}]
    end

    test "is refused for a user outside the organization", %{conn2: conn2, org: org, product: product, device: device} do
      assert_error_sent(404, fn -> get(conn2, path(conn2, org, product, device)) end)
      |> assert_authorization_error(404)
    end
  end

  describe "index, filtered" do
    setup %{device: device, now: now} do
      raise_alarm(device, "LowMemory", "low", DateTime.add(now, -300))
      raise_alarm(device, "CableDown", "eth0", DateTime.add(now, -200))
      clear_alarm(device, "LowMemory", DateTime.add(now, -100))
    end

    test "by alarm name, comma separated", %{conn: conn, org: org, product: product, device: device} do
      conn = get(conn, path(conn, org, product, device, alarm: "LowMemory,Nope", order: "asc"))

      assert events(json_response(conn, 200)) == [{"LowMemory", "raised"}, {"LowMemory", "resolved"}]
    end

    test "by event", %{conn: conn, org: org, product: product, device: device} do
      conn = get(conn, path(conn, org, product, device, event: "raised", order: "asc"))

      assert events(json_response(conn, 200)) == [{"LowMemory", "raised"}, {"CableDown", "raised"}]
    end

    test "by a window of time, which pages with before", %{
      conn: conn,
      org: org,
      product: product,
      device: device,
      now: now
    } do
      params = [since: DateTime.to_iso8601(DateTime.add(now, -250)), limit: 1]
      page = json_response(get(conn, path(conn, org, product, device, params)), 200)
      assert events(page) == [{"LowMemory", "resolved"}]

      [%{"timestamp" => oldest}] = page["data"]
      next = json_response(get(conn, path(conn, org, product, device, params ++ [before: oldest])), 200)
      assert events(next) == [{"CableDown", "raised"}]
    end

    test "refuses a timestamp it cannot read", %{conn: conn, org: org, product: product, device: device} do
      conn = get(conn, path(conn, org, product, device, since: "yesterday"))

      assert json_response(conn, 422)["errors"]["detail"] =~ "since must be an ISO 8601 timestamp"
    end
  end

  describe "index, without an analytics database" do
    setup do
      original = Application.get_env(:nerves_hub, :analytics_enabled)
      Application.put_env(:nerves_hub, :analytics_enabled, false)

      on_exit(fn -> Application.put_env(:nerves_hub, :analytics_enabled, original) end)
    end

    test "says so instead of answering with an empty list", %{conn: conn, org: org, product: product, device: device} do
      conn = get(conn, path(conn, org, product, device))

      assert json_response(conn, 501)["errors"]["detail"] =~ "device alarm history is not stored"
    end
  end
end
