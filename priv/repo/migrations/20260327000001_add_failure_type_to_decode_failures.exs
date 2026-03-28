defmodule BtcTxFeed.Repo.Migrations.AddFailureTypeToDecodeFailures do
  use Ecto.Migration

  def change do
    alter table(:decode_failures) do
      add :failure_type, :string, null: false, default: "decode"
    end
  end
end
