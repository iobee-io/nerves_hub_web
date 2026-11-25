defmodule NervesHubWeb.API.DeviceUpdateAttemptControllerTest do
  # Not async: these tests read and write the AnalyticsRepo (ClickHouse), which
  # has no sandbox, and one of them toggles the global :analytics_enabled.
  use NervesHubWeb.APIConnCase, async: false

  alias NervesHub.Analytics.Buffer
  alias NervesHub.AnalyticsRepo
  alias NervesHub.Devices
  alias NervesHub.Devices.DeviceUpdateHistory
  alias NervesHub.Devices.UpdateHistory
  alias NervesHub.Fixtures

  setup %{org: org, product: product, user: user, tmp_dir: tmp_dir} do
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
    source = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    target = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    {:ok, device} = Devices.create_device(product, %{identifier: "device-1234"})
    {:ok, other} = Devices.create_device(product, %{identifier: "device-5678"})

    :ok = Buffer.flush(DeviceUpdateHistory)
    AnalyticsRepo.query!("TRUNCATE TABLE device_update_history")

    on_exit(fn ->
      :ok = Buffer.flush(DeviceUpdateHistory)
      AnalyticsRepo.query!("TRUNCATE TABLE device_update_history")
    end)

    [device: device, other: other, source: source, target: target, now: DateTime.utc_now()]
  end

  defp path(conn, org, product, device, params \\ []) do
    Routes.api_device_update_attempt_path(conn, :index, org.name, product.name, device.identifier, params)
  end

  defp attempt(device, status, at, firmwares, opts \\ []) do
    :ok =
      UpdateHistory.record(
        device,
        status,
        [timestamp: at, source_firmware_uuid: firmwares.source.uuid, target_firmware_uuid: firmwares.target.uuid] ++
          opts
      )

    :ok = Buffer.flush(DeviceUpdateHistory)
  end

  defp statuses(response), do: Enum.map(response["data"], & &1["status"])

  describe "index" do
    test "is empty for a device that never updated", %{conn: conn, org: org, product: product, device: device} do
      assert json_response(get(conn, path(conn, org, product, device)), 200) == %{"data" => []}
    end

    test "returns attempts newest first, with the firmware versions", %{
      conn: conn,
      org: org,
      product: product,
      device: device,
      source: source,
      target: target,
      now: now
    } do
      firmwares = %{source: source, target: target}
      attempt(device, :failed, DateTime.add(now, -120), firmwares, reason: "fwup: signature check failed")
      attempt(device, :succeeded, DateTime.add(now, -60), firmwares)

      response = json_response(get(conn, path(conn, org, product, device)), 200)

      assert statuses(response) == ["succeeded", "failed"]

      assert [
               %{"reason" => nil},
               %{
                 "reason" => "fwup: signature check failed",
                 "source" => %{"uuid" => source_uuid, "version" => source_version},
                 "target" => %{"uuid" => target_uuid},
                 "deployment_group" => nil
               }
             ] = response["data"]

      assert {source_uuid, source_version, target_uuid} == {source.uuid, source.version, target.uuid}
    end

    test "does not return another device's attempts", %{
      conn: conn,
      org: org,
      product: product,
      device: device,
      other: other,
      source: source,
      target: target,
      now: now
    } do
      attempt(other, :failed, now, %{source: source, target: target})

      assert json_response(get(conn, path(conn, org, product, device)), 200) == %{"data" => []}
    end

    test "is reachable on the short device URL", %{conn: conn, device: device, source: source, target: target, now: now} do
      attempt(device, :succeeded, now, %{source: source, target: target})

      conn = get(conn, Routes.api_device_update_attempt_path(conn, :index, device.identifier))

      assert statuses(json_response(conn, 200)) == ["succeeded"]
    end

    test "is refused for a user outside the organization", %{conn2: conn2, org: org, product: product, device: device} do
      assert_error_sent(404, fn -> get(conn2, path(conn2, org, product, device)) end)
      |> assert_authorization_error(404)
    end
  end

  describe "index, filtered" do
    setup %{device: device, source: source, target: target, now: now} do
      firmwares = %{source: source, target: target}
      attempt(device, :failed, DateTime.add(now, -300), firmwares)
      attempt(device, :rescheduled, DateTime.add(now, -200), firmwares)
      attempt(device, :succeeded, DateTime.add(now, -100), firmwares)
    end

    test "by status, comma separated", %{conn: conn, org: org, product: product, device: device} do
      conn = get(conn, path(conn, org, product, device, status: "failed,succeeded", order: "asc"))

      assert statuses(json_response(conn, 200)) == ["failed", "succeeded"]
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
      assert statuses(page) == ["succeeded"]

      [%{"timestamp" => oldest}] = page["data"]
      next = json_response(get(conn, path(conn, org, product, device, params ++ [before: oldest])), 200)
      assert statuses(next) == ["rescheduled"]
    end

    test "refuses a limit out of range", %{conn: conn, org: org, product: product, device: device} do
      conn = get(conn, path(conn, org, product, device, limit: "0"))

      assert json_response(conn, 422)["errors"]["detail"] =~ "limit must be a whole number between 1 and 1000"
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

      assert json_response(conn, 501)["errors"]["detail"] =~ "device update history is not stored"
    end
  end
end
