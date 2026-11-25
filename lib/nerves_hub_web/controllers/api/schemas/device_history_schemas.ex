defmodule NervesHubWeb.API.Schemas.DeviceHistorySchemas do
  @moduledoc false

  alias OpenApiSpex.Schema

  require OpenApiSpex

  defmodule DeviceAlarmTransition do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      description: "One alarm transition on a device: a raise or a resolve",
      type: :object,
      properties: %{
        timestamp: %Schema{type: :string, format: :"date-time", description: "When the transition happened"},
        alarm: %Schema{type: :string, description: "The alarm's name, without an `Elixir.` prefix"},
        event: %Schema{
          type: :string,
          enum: ["raised", "resolved"],
          description: "Whether the alarm was raised or resolved"
        },
        description: %Schema{
          type: :string,
          nullable: true,
          description: "What the device said about the alarm when raising it; null on a resolve"
        }
      },
      example: %{
        "timestamp" => "2026-08-16T09:14:00.123456Z",
        "alarm" => "LowMemory",
        "event" => "raised",
        "description" => "largest free block 24576 bytes, under 32768"
      }
    })
  end

  defmodule DeviceAlarmListResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      description: "Device alarm history response",
      type: :object,
      properties: %{
        data: %Schema{
          description: "The matching transitions, newest first unless `order=asc` was given",
          type: :array,
          items: DeviceAlarmTransition
        }
      },
      example: %{
        "data" => [
          %{
            "timestamp" => "2026-08-16T09:20:00.000000Z",
            "alarm" => "LowMemory",
            "event" => "resolved",
            "description" => nil
          },
          %{
            "timestamp" => "2026-08-16T09:14:00.123456Z",
            "alarm" => "LowMemory",
            "event" => "raised",
            "description" => "largest free block 24576 bytes, under 32768"
          }
        ]
      }
    })
  end

  defmodule DeviceUpdateAttemptFirmware do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      description: "A firmware an update attempt names",
      type: :object,
      nullable: true,
      properties: %{
        uuid: %Schema{type: :string, format: :uuid},
        version: %Schema{
          type: :string,
          nullable: true,
          description: "Null when the product has no firmware with this UUID"
        }
      },
      example: %{"uuid" => "151fa836-f0d1-22f8-3c17-51ce87761c7b", "version" => "1.4.0"}
    })
  end

  defmodule DeviceUpdateAttempt do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      description: "How one firmware update attempt on a device ended",
      type: :object,
      properties: %{
        timestamp: %Schema{type: :string, format: :"date-time", description: "When the attempt ended"},
        status: %Schema{
          type: :string,
          enum: ["succeeded", "failed", "ignored", "rescheduled", "expired", "abandoned"],
          description: "How it ended. All but `succeeded` and `rescheduled` count as failures"
        },
        reason: %Schema{type: :string, nullable: true, description: "What the device said, when it said anything"},
        source: DeviceUpdateAttemptFirmware,
        target: DeviceUpdateAttemptFirmware,
        deployment_group: %Schema{
          type: :string,
          nullable: true,
          description: "The deployment group that sent the update, if it still exists"
        }
      },
      example: %{
        "timestamp" => "2026-08-16T09:14:00.123456Z",
        "status" => "failed",
        "reason" => "fwup: signature check failed",
        "source" => %{"uuid" => "2c4a1f0e-5b9e-4c8e-9d0a-3f1e7b6a8c21", "version" => "1.3.2"},
        "target" => %{"uuid" => "151fa836-f0d1-22f8-3c17-51ce87761c7b", "version" => "1.4.0"},
        "deployment_group" => "canary"
      }
    })
  end

  defmodule DeviceUpdateAttemptListResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      description: "Device update attempts response",
      type: :object,
      properties: %{
        data: %Schema{
          description: "The matching attempts, newest first unless `order=asc` was given",
          type: :array,
          items: DeviceUpdateAttempt
        }
      },
      example: %{
        "data" => [
          %{
            "timestamp" => "2026-08-16T09:14:00.123456Z",
            "status" => "succeeded",
            "reason" => nil,
            "source" => %{"uuid" => "2c4a1f0e-5b9e-4c8e-9d0a-3f1e7b6a8c21", "version" => "1.3.2"},
            "target" => %{"uuid" => "151fa836-f0d1-22f8-3c17-51ce87761c7b", "version" => "1.4.0"},
            "deployment_group" => "canary"
          }
        ]
      }
    })
  end
end
