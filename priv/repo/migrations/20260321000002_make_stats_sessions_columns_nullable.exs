defmodule BtcTxFeed.Repo.Migrations.MakeStatsSessionsColumnsNullable do
  use Ecto.Migration

  # SQLite does not support ALTER COLUMN, so the table is rebuilt.
  # decode_failures.stats_session_id already references stats_sessions by name;
  # dropping and recreating stats_sessions does not affect that FK metadata.

  def up do
    execute """
    CREATE TABLE stats_sessions_new (
      id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
      started_at TEXT NOT NULL,
      ended_at TEXT,
      counters BLOB,
      total_decoded INTEGER NOT NULL DEFAULT 0,
      total_failed INTEGER NOT NULL DEFAULT 0
    )
    """

    execute "INSERT INTO stats_sessions_new SELECT * FROM stats_sessions"
    execute "DROP TABLE stats_sessions"
    execute "ALTER TABLE stats_sessions_new RENAME TO stats_sessions"
  end

  def down do
    execute """
    CREATE TABLE stats_sessions_old (
      id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
      started_at TEXT NOT NULL,
      ended_at TEXT NOT NULL,
      counters BLOB NOT NULL,
      total_decoded INTEGER NOT NULL DEFAULT 0,
      total_failed INTEGER NOT NULL DEFAULT 0
    )
    """

    execute "INSERT INTO stats_sessions_old SELECT * FROM stats_sessions WHERE ended_at IS NOT NULL AND counters IS NOT NULL"
    execute "DROP TABLE stats_sessions"
    execute "ALTER TABLE stats_sessions_old RENAME TO stats_sessions"
  end
end
