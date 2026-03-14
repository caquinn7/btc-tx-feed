defmodule BtcTxFeed.Test.WebSocketServer do
  @moduledoc """
  A minimal Bandit + WebSock server for integration-testing `WebSocketClient`.

  Start it in tests with:

      port = WebSocketServer.start_server!(EchoHandler)
      {:ok, client} = WebSocketClient.connect("ws://localhost:\#{port}/ws")

  Available handlers:

    - `EchoHandler`   — echoes every text frame back verbatim
    - `PingHandler`   — sends a ping to the client immediately after init
    - `CloseHandler`  — sends a close frame immediately after init
    - `SilentHandler` — does nothing (useful for testing connect-only)
  """

  defmodule Plug do
    @behaviour Elixir.Plug

    def init(handler), do: handler

    def call(conn, handler) do
      WebSockAdapter.upgrade(conn, handler, [], [])
    end
  end

  defmodule EchoHandler do
    @behaviour WebSock

    @impl WebSock
    def init(state), do: {:ok, state}

    @impl WebSock
    def handle_in({text, opcode: :text}, state), do: {:push, {:text, text}, state}
    def handle_in({data, opcode: :binary}, state), do: {:push, {:binary, data}, state}
    def handle_in(_, state), do: {:ok, state}

    @impl WebSock
    def handle_control({_data, opcode: :ping}, state), do: {:ok, state}
    def handle_control(_, state), do: {:ok, state}

    @impl WebSock
    def handle_info(_, state), do: {:ok, state}

    @impl WebSock
    def terminate(_, _), do: :ok
  end

  defmodule PingHandler do
    @behaviour WebSock

    @impl WebSock
    def init(state) do
      # Push a server-initiated ping
      {:push, {:ping, ""}, state}
    end

    @impl WebSock
    def handle_in(_, state), do: {:ok, state}

    @impl WebSock
    def handle_control(_, state), do: {:ok, state}

    @impl WebSock
    def handle_info(_, state), do: {:ok, state}

    @impl WebSock
    def terminate(_, _), do: :ok
  end

  defmodule CloseHandler do
    @behaviour WebSock

    @impl WebSock
    def init(state), do: {:stop, :normal, state}

    @impl WebSock
    def handle_in(_, state), do: {:ok, state}

    @impl WebSock
    def handle_control(_, state), do: {:ok, state}

    @impl WebSock
    def handle_info(_, state), do: {:ok, state}

    @impl WebSock
    def terminate(_, _), do: :ok
  end

  defmodule SilentHandler do
    @behaviour WebSock

    @impl WebSock
    def init(state), do: {:ok, state}

    @impl WebSock
    def handle_in(_, state), do: {:ok, state}

    @impl WebSock
    def handle_control(_, state), do: {:ok, state}

    @impl WebSock
    def handle_info(_, state), do: {:ok, state}

    @impl WebSock
    def terminate(_, _), do: :ok
  end

  @doc """
  Returns a Bandit child spec suitable for `start_supervised!/1` in tests.
  Binds to port 0 (OS-assigned). After starting, use
  `ThousandIsland.listener_info/1` to retrieve the actual port.
  """
  def child_spec(handler) do
    {Bandit, plug: {__MODULE__.Plug, handler}, scheme: :http, port: 0, startup_log: false}
  end
end
