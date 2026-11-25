defmodule NervesHubWeb.API.HistoryParams do
  @moduledoc """
  The query parameters every device history endpoint reads the same way:
  `since`, `before`, `limit` and `order`.

  Device logs, metrics, alarms and update attempts are all read-only history
  in the analytics database, windowed and paged alike. Each parser returns
  `{:ok, value}` or the `{:error, {:invalid_query_param, reason}}` the fallback
  controller answers with a 422, so a controller chains them in one `with`.
  """

  @default_limit 100
  @max_limit 1000

  @doc "The page size when the request gives none."
  @spec default_limit() :: 100
  def default_limit(), do: @default_limit

  @doc "The largest page a request may ask for."
  @spec max_limit() :: 1000
  def max_limit(), do: @max_limit

  @doc """
  `since`, `before`, `limit` and `order` from `params`, as the keyword list
  the history queries take.
  """
  @spec window(map()) :: {:ok, keyword()} | {:error, {:invalid_query_param, String.t()}}
  def window(params) do
    with {:ok, since} <- timestamp("since", params["since"]),
         {:ok, before} <- timestamp("before", params["before"]),
         {:ok, limit} <- limit(params["limit"]),
         {:ok, order} <- order(params["order"]) do
      {:ok, [since: since, before: before, limit: limit, order: order]}
    end
  end

  @doc "An ISO 8601 timestamp named `name`, or nil when it is absent."
  @spec timestamp(String.t(), term()) :: {:ok, DateTime.t() | nil} | {:error, {:invalid_query_param, String.t()}}
  def timestamp(_name, nil), do: {:ok, nil}
  def timestamp(_name, ""), do: {:ok, nil}

  def timestamp(name, value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, timestamp, _offset} ->
        {:ok, timestamp}

      {:error, _reason} ->
        {:error,
         {:invalid_query_param,
          "#{name} must be an ISO 8601 timestamp, eg. 2026-08-16T09:14:00Z, got #{inspect(value)}."}}
    end
  end

  def timestamp(name, value) do
    {:error, {:invalid_query_param, "#{name} must be an ISO 8601 timestamp, got #{inspect(value)}."}}
  end

  @doc "A page size from 1 to #{@max_limit}, #{@default_limit} when absent."
  @spec limit(term()) :: {:ok, pos_integer()} | {:error, {:invalid_query_param, String.t()}}
  def limit(nil), do: {:ok, @default_limit}
  def limit(""), do: {:ok, @default_limit}

  def limit(limit) when is_integer(limit), do: validate_limit(limit, limit)

  def limit(limit) when is_binary(limit) do
    case Integer.parse(limit) do
      {parsed, ""} -> validate_limit(parsed, limit)
      _other -> invalid_limit(limit)
    end
  end

  def limit(limit), do: invalid_limit(limit)

  defp validate_limit(limit, _raw) when limit >= 1 and limit <= @max_limit, do: {:ok, limit}
  defp validate_limit(_limit, raw), do: invalid_limit(raw)

  defp invalid_limit(raw) do
    {:error, {:invalid_query_param, "limit must be a whole number between 1 and #{@max_limit}, got #{inspect(raw)}."}}
  end

  @doc "`asc` or `desc`, newest first (`desc`) when absent."
  @spec order(term()) :: {:ok, :asc | :desc} | {:error, {:invalid_query_param, String.t()}}
  def order(nil), do: {:ok, :desc}
  def order(""), do: {:ok, :desc}
  def order("desc"), do: {:ok, :desc}
  def order("asc"), do: {:ok, :asc}

  def order(order), do: {:error, {:invalid_query_param, "order must be asc or desc, got #{inspect(order)}."}}

  @doc """
  A comma-separated list (or a repeated parameter) named `name`, trimmed, nil
  when absent or empty. Values are not checked against a fixed list: a value
  nothing has is a filter that matches nothing, not an error.
  """
  @spec list(String.t(), term()) :: {:ok, [String.t()] | nil} | {:error, {:invalid_query_param, String.t()}}
  def list(_name, nil), do: {:ok, nil}
  def list(name, value) when is_binary(value), do: list(name, String.split(value, ","))

  def list(name, values) when is_list(values) do
    if Enum.all?(values, &is_binary/1) do
      case Enum.reject(Enum.map(values, &String.trim/1), &(&1 == "")) do
        [] -> {:ok, nil}
        values -> {:ok, values}
      end
    else
      invalid_list(name, values)
    end
  end

  def list(name, value), do: invalid_list(name, value)

  defp invalid_list(name, value),
    do: {:error, {:invalid_query_param, "#{name} must be a string, got #{inspect(value)}."}}
end
