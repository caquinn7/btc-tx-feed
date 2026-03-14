defmodule BtcTxFeed.WebSocketClient do
  @moduledoc """
  Pure-functional wrapper around Mint's WebSocket plumbing.

  Owns the Mint connection handles and the HTTP-upgrade state machine.
  Has no side effects: no Logger calls, no PubSub, no process interactions.

  `stream/2` returns application-level events that the calling process
  is responsible for acting on:

    - `:connected`        — WebSocket upgrade completed
    - `{:text, binary()}` — text frame received
    - `{:close, reason}`  — close frame received; the connection should be torn down

  Server-initiated ping frames are handled internally: a pong is sent immediately
  and the frame is never surfaced to the caller.
  """

  require Mint.HTTP

  @dialyzer {:nowarn_function, [reduce_responses: 3]}

  defstruct [:conn, :websocket, :request_ref, :status, :resp_headers]

  @type t :: %__MODULE__{
          conn: Mint.HTTP.t() | nil,
          websocket: Mint.WebSocket.t() | nil,
          request_ref: Mint.Types.request_ref() | nil,
          status: non_neg_integer() | nil,
          resp_headers: list() | nil
        }

  @type event :: :connected | {:text, binary()} | {:close, term()}

  @spec connect(String.t()) :: {:ok, t()} | {:error, term()}
  def connect(url) do
    uri = URI.parse(url)
    {http_scheme, ws_scheme} = if uri.scheme == "wss", do: {:https, :wss}, else: {:http, :ws}

    with {:ok, conn} <- Mint.HTTP.connect(http_scheme, uri.host, uri.port, protocols: [:http1]),
         {:ok, conn, ref} <- Mint.WebSocket.upgrade(ws_scheme, conn, uri.path, []) do
      {:ok, %__MODULE__{conn: conn, request_ref: ref}}
    else
      {:error, _conn, reason} -> {:error, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec send_frame(t(), term()) :: {:ok, t()} | {:error, t(), term()}
  def send_frame(%__MODULE__{} = client, frame) do
    case Mint.WebSocket.encode(client.websocket, frame) do
      {:ok, websocket, data} ->
        client = %{client | websocket: websocket}

        case Mint.WebSocket.stream_request_body(client.conn, client.request_ref, data) do
          {:ok, conn} -> {:ok, %{client | conn: conn}}
          {:error, conn, reason} -> {:error, %{client | conn: conn}, reason}
        end

      {:error, websocket, reason} ->
        {:error, %{client | websocket: websocket}, reason}
    end
  end

  @spec stream(t() | nil, term()) :: {:ok, t(), [event()]} | {:error, term()} | :unknown
  def stream(nil, _message), do: :unknown

  def stream(%__MODULE__{} = client, message) do
    case Mint.WebSocket.stream(client.conn, message) do
      {:ok, conn, responses} ->
        reduce_responses(%{client | conn: conn}, responses, [])

      {:error, _conn, reason, _responses} ->
        {:error, reason}

      :unknown ->
        :unknown
    end
  end

  @spec close(t() | nil) :: :ok
  def close(nil), do: :ok

  def close(%__MODULE__{conn: conn}) do
    Mint.HTTP.close(conn)
    :ok
  end

  @spec connected?(t() | nil) :: boolean()
  def connected?(nil), do: false
  def connected?(%__MODULE__{websocket: websocket}), do: websocket != nil

  # --- Private: HTTP upgrade response reduction ---

  # Binding `ref` in both the struct pattern and the response tuple is an equality
  # constraint — the clause only matches when client.request_ref == ref in the tuple.
  defp reduce_responses(%{request_ref: ref} = client, [{:status, ref, status} | rest], events) do
    reduce_responses(%{client | status: status}, rest, events)
  end

  defp reduce_responses(
         %{request_ref: ref} = client,
         [{:headers, ref, resp_headers} | rest],
         events
       ) do
    reduce_responses(%{client | resp_headers: resp_headers}, rest, events)
  end

  defp reduce_responses(%{request_ref: ref} = client, [{:done, ref} | rest], events) do
    case Mint.WebSocket.new(client.conn, ref, client.status, client.resp_headers) do
      {:ok, conn, websocket} ->
        reduce_responses(%{client | conn: conn, websocket: websocket}, rest, [:connected | events])

      {:error, _conn, reason} ->
        {:error, reason}
    end
  end

  defp reduce_responses(
         %{request_ref: ref, websocket: websocket} = client,
         [{:data, ref, data} | rest],
         events
       )
       when not is_nil(websocket) do
    case Mint.WebSocket.decode(client.websocket, data) do
      {:ok, websocket, frames} ->
        case reduce_frames(%{client | websocket: websocket}, frames, events) do
          {:ok, client, events} -> reduce_responses(client, rest, events)
          # close frame — stop processing further responses
          {:close, client, events} -> {:ok, client, Enum.reverse(events)}
        end

      {:error, websocket, _reason} ->
        reduce_responses(%{client | websocket: websocket}, rest, events)
    end
  end

  defp reduce_responses(client, [_ | rest], events) do
    reduce_responses(client, rest, events)
  end

  defp reduce_responses(client, [], events) do
    {:ok, client, Enum.reverse(events)}
  end

  # --- Private: WebSocket frame reduction ---

  defp reduce_frames(client, [], events) do
    {:ok, client, events}
  end

  defp reduce_frames(client, [{:close, _code, reason} | _], events) do
    {:close, client, [{:close, reason} | events]}
  end

  defp reduce_frames(client, [{:ping, data} | rest], events) do
    case send_frame(client, {:pong, data}) do
      {:ok, client} -> reduce_frames(client, rest, events)
      {:error, client, _reason} -> reduce_frames(client, rest, events)
    end
  end

  defp reduce_frames(client, [{:pong, _} | rest], events) do
    reduce_frames(client, rest, events)
  end

  defp reduce_frames(client, [{:text, text} | rest], events) do
    reduce_frames(client, rest, [{:text, text} | events])
  end

  defp reduce_frames(client, [_ | rest], events) do
    reduce_frames(client, rest, events)
  end
end
