defmodule NervesHubWeb.API.OpenAPI.DeviceHistoryControllerSpecs do
  @moduledoc """
  OpenAPI operations for `NervesHubWeb.API.DeviceAlarmController` and
  `NervesHubWeb.API.DeviceUpdateAttemptController`.

  Both are served from two URLs — the product-scoped one and the short device
  one — and only the first carries org and product path parameters, so each is
  described here twice rather than with a single `operation/2` in the
  controller. They share the time window and paging parameters.
  """

  import OpenApiSpex.Operation, only: [response: 3]

  alias NervesHubWeb.API.HistoryParams
  alias NervesHubWeb.API.OpenAPI.SchemaHelpers
  alias NervesHubWeb.API.Schemas.DeviceHistorySchemas
  alias NervesHubWeb.API.Schemas.ErrorSchemas

  @window_parameters [
    %OpenApiSpex.Parameter{
      name: :since,
      in: :query,
      description: "Only entries at or after this ISO 8601 timestamp",
      required: false,
      schema: %OpenApiSpex.Schema{type: :string, format: :"date-time"},
      example: "2026-08-16T09:00:00Z"
    },
    %OpenApiSpex.Parameter{
      name: :before,
      in: :query,
      description:
        "Only entries strictly before this ISO 8601 timestamp. To page back through history, pass the timestamp of the oldest entry you received",
      required: false,
      schema: %OpenApiSpex.Schema{type: :string, format: :"date-time"},
      example: "2026-08-16T09:14:00.123456Z"
    },
    %OpenApiSpex.Parameter{
      name: :limit,
      in: :query,
      description: "How many entries to return, from 1 to #{HistoryParams.max_limit()}",
      required: false,
      schema: %OpenApiSpex.Schema{type: :integer, default: HistoryParams.default_limit()},
      example: "250"
    },
    %OpenApiSpex.Parameter{
      name: :order,
      in: :query,
      description: "`desc` for newest first, `asc` for oldest first",
      required: false,
      schema: %OpenApiSpex.Schema{type: :string, enum: ["desc", "asc"], default: "desc"},
      example: "asc"
    }
  ]

  @operations %{
    alarms: %{
      segment: "alarms",
      tag: "Device Alarms",
      controller: "DeviceAlarmController",
      summary: "List the Alarm transitions of a Device",
      description: """
      Every alarm this device raised or resolved, newest first. Kept in the
      analytics database, so a deployment without one answers 501.

      To page back through history, ask for a `limit` and then pass the
      `timestamp` of the oldest transition you received as the next request's
      `before`.
      """,
      filters: [
        %OpenApiSpex.Parameter{
          name: :alarm,
          in: :query,
          description: "Only these alarms, by name. Comma separated for more than one",
          required: false,
          schema: %OpenApiSpex.Schema{type: :string},
          example: "LowMemory"
        },
        %OpenApiSpex.Parameter{
          name: :event,
          in: :query,
          description: "Only `raised` or only `resolved` transitions",
          required: false,
          schema: %OpenApiSpex.Schema{type: :string},
          example: "raised"
        }
      ],
      response: DeviceHistorySchemas.DeviceAlarmListResponse
    },
    update_attempts: %{
      segment: "update_attempts",
      tag: "Device Update Attempts",
      controller: "DeviceUpdateAttemptController",
      summary: "List how the Update attempts of a Device ended",
      description: """
      Every firmware update attempt this device finished, newest first, and
      how it ended. Kept in the analytics database, so a deployment without
      one answers 501.

      To page back through history, ask for a `limit` and then pass the
      `timestamp` of the oldest attempt you received as the next request's
      `before`.
      """,
      filters: [
        %OpenApiSpex.Parameter{
          name: :status,
          in: :query,
          description:
            "Only attempts that ended this way: succeeded, failed, ignored, rescheduled, expired or abandoned. Comma separated for more than one",
          required: false,
          schema: %OpenApiSpex.Schema{type: :string},
          example: "failed,expired,abandoned"
        }
      ],
      response: DeviceHistorySchemas.DeviceUpdateAttemptListResponse
    }
  }

  def add_operations(openapi) do
    for operation <- Map.keys(@operations), structure <- [:long, :short], reduce: openapi do
      openapi -> index_action(openapi, @operations[operation], structure)
    end
  end

  defp index_action(openapi, operation, structure) do
    {path, tags, parameters} = path_structure(structure, operation)

    list_operation = %OpenApiSpex.Operation{
      tags: tags,
      summary: operation.summary,
      description: operation.description,
      operationId: "NervesHubWeb.API.#{operation.controller}.index.#{structure}",
      parameters: parameters ++ operation.filters ++ @window_parameters,
      responses:
        %{
          200 => response(operation.summary, "application/json", operation.response),
          422 => response("Unusable query parameter", "application/json", ErrorSchemas.ErrorResponse),
          501 =>
            response(
              "This platform has no analytics database, so no history is stored",
              "application/json",
              ErrorSchemas.ErrorResponse
            )
        }
        |> Map.merge(SchemaHelpers.common_errors())
        |> Map.merge(SchemaHelpers.not_found_error()),
      callbacks: %{},
      security: [%{"bearer_auth" => []}],
      extensions: %{}
    }

    Map.put(openapi, :paths, Map.put(openapi.paths, path, %OpenApiSpex.PathItem{get: list_operation}))
  end

  defp path_structure(:short, operation) do
    {"/api/devices/{identifier}/#{operation.segment}", ["Devices (short URL)"], [SchemaHelpers.device_param()]}
  end

  defp path_structure(:long, operation) do
    {"/api/orgs/{org_name}/products/{product_name}/devices/{identifier}/#{operation.segment}", [operation.tag],
     [SchemaHelpers.org_param(), SchemaHelpers.product_param(), SchemaHelpers.device_param()]}
  end
end
