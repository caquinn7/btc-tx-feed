defmodule BtcTxFeed.WebSocketClientTest do
  use ExUnit.Case, async: true

  alias BtcTxFeed.WebSocketClient
  alias BtcTxFeed.Test.WebSocketServer

  defp start_server!(handler) do
    server = start_supervised!(WebSocketServer.child_spec(handler))
    {:ok, {_ip, port}} = ThousandIsland.listener_info(server)
    port
  end

  # --- Pure unit tests (no server required) ---

  describe "connected?/1" do
    test "returns false for nil" do
      assert WebSocketClient.connected?(nil) == false
    end

    test "returns false when websocket field is nil" do
      assert WebSocketClient.connected?(%WebSocketClient{}) == false
    end
  end

  describe "close/1" do
    test "accepts nil and returns :ok" do
      assert WebSocketClient.close(nil) == :ok
    end
  end

  describe "stream/2" do
    test "returns :unknown for nil client" do
      assert WebSocketClient.stream(nil, :some_message) == :unknown
    end
  end

  # --- Integration tests against a local Bandit server ---

  describe "connect/1" do
    test "returns {:ok, client} on successful WebSocket upgrade" do
      port = start_server!(WebSocketServer.SilentHandler)

      assert {:ok, client} = WebSocketClient.connect("ws://localhost:#{port}/ws")

      # websocket field is nil until the server's 101 response is streamed;
      # drain to process the upgrade and then check connected?
      assert {:ok, client, events} = drain_stream(client)
      assert :connected in events
      assert WebSocketClient.connected?(client)

      WebSocketClient.close(client)
    end

    test "returns {:error, reason} when server is not reachable" do
      assert {:error, _reason} = WebSocketClient.connect("ws://localhost:1/ws")
    end
  end

  describe "stream/2 events" do
    test "emits :connected event on successful upgrade" do
      port = start_server!(WebSocketServer.SilentHandler)
      {:ok, client} = WebSocketClient.connect("ws://localhost:#{port}/ws")

      # Drain the upgrade messages from the mailbox
      assert {:ok, _client, events} = drain_stream(client)
      assert :connected in events

      WebSocketClient.close(client)
    end

    test "emits {:text, text} event for a server text frame" do
      port = start_server!(WebSocketServer.EchoHandler)
      {:ok, client} = WebSocketClient.connect("ws://localhost:#{port}/ws")

      {:ok, client, _} = drain_stream(client)

      # Send a text frame; EchoHandler will echo it back
      {:ok, client} = WebSocketClient.send_frame(client, {:text, "hello"})

      assert {:ok, _client, events} = drain_stream(client)
      assert {:text, "hello"} in events
    end

    test "emits {:close, reason} event when server closes the connection" do
      port = start_server!(WebSocketServer.CloseHandler)
      {:ok, client} = WebSocketClient.connect("ws://localhost:#{port}/ws")

      # CloseHandler stops immediately; we may get a clean close frame or a
      # transport error depending on timing — both mean the server closed.
      result = drain_stream(client, retries: 20)

      case result do
        {:ok, _client, events} ->
          assert Enum.any?(events, fn
                   {:close, _} -> true
                   _ -> false
                 end)

        {:error, _reason} ->
          :ok
      end
    end

    test "handles server-initiated ping without surfacing it as an event" do
      port = start_server!(WebSocketServer.PingHandler)
      {:ok, client} = WebSocketClient.connect("ws://localhost:#{port}/ws")

      {:ok, _client, events} = drain_stream(client, retries: 20)

      # :connected may appear, but a raw {:ping, _} should never be in events
      refute Enum.any?(events, fn
               {:ping, _} -> true
               _ -> false
             end)
    end
  end

  describe "send_frame/2" do
    test "returns {:ok, updated_client} on success" do
      port = start_server!(WebSocketServer.SilentHandler)
      {:ok, client} = WebSocketClient.connect("ws://localhost:#{port}/ws")
      {:ok, client, _} = drain_stream(client)

      assert {:ok, _client} = WebSocketClient.send_frame(client, {:text, "ping"})
    end
  end

  # --- Helpers ---

  # Drains the process mailbox by repeatedly calling stream/2 until no more
  # messages arrive within a short window. Returns accumulated events.
  defp drain_stream(client, opts \\ []) do
    retries = Keyword.get(opts, :retries, 10)
    do_drain(client, [], retries)
  end

  defp do_drain(client, acc_events, 0), do: {:ok, client, acc_events}

  defp do_drain(client, acc_events, retries) do
    receive do
      msg ->
        case WebSocketClient.stream(client, msg) do
          {:ok, client, events} ->
            do_drain(client, acc_events ++ events, retries)

          {:error, reason} ->
            {:error, reason}

          :unknown ->
            do_drain(client, acc_events, retries - 1)
        end
    after
      50 ->
        do_drain(client, acc_events, retries - 1)
    end
  end
end
