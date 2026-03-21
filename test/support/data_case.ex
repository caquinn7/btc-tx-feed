defmodule BtcTxFeed.DataCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      alias BtcTxFeed.Repo

      import Ecto
      import Ecto.Query
    end
  end

  setup tags do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(BtcTxFeed.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    :ok
  end
end
