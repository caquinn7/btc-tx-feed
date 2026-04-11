defmodule BtcTxFeed.RetainedTransaction do
  use Ecto.Schema
  import Ecto.Changeset

  schema "retained_transactions" do
    field(:txid, :string)
    field(:corpus_code, :string)
    field(:corpus_label, :string)
    field(:raw_hex, :string)
    field(:matched_rule, :string)

    timestamps(updated_at: false)
  end

  def changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:txid, :corpus_code, :corpus_label, :raw_hex, :matched_rule])
    |> validate_required([:txid, :corpus_code, :corpus_label, :raw_hex, :matched_rule])
  end
end
