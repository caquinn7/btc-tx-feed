defmodule BtcTxFeed.TxParser do
  @moduledoc """
  Parses raw Bitcoin transaction bytes using the `btc_tx` library and returns
  a structured map of details for display.
  """

  @doc """
  Accepts raw transaction bytes and returns `{:ok, details_map}` or
  `{:error, reason}`.
  """
  def parse(raw_bytes) when is_binary(raw_bytes) do
    with {:ok, tx} <-
           :btc_tx.decode_with_policy(raw_bytes, BtcTxFeed.DecodePolicy.to_btc_tx_policy()) do
      {:ok, build_details(tx)}
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp build_details(tx) do
    is_segwit = :btc_tx.is_segwit(tx)
    inputs = :btc_tx.get_inputs(tx)
    outputs = :btc_tx.get_outputs(tx)

    base = %{
      version: :btc_tx.get_version(tx),
      is_segwit: is_segwit,
      lock_time: :btc_tx.get_lock_time(tx),
      has_coinbase_marker: :btc_tx.has_coinbase_marker(tx),
      input_count: length(inputs),
      output_count: length(outputs),
      inputs: extract_inputs(inputs),
      outputs: extract_outputs(outputs),
      witnesses: extract_witnesses(tx, is_segwit)
    }

    case :btc_tx.validate_consensus(tx) do
      {:ok, validated} ->
        stripped = :btc_tx.to_stripped_bytes(validated)
        witness_bytes = :btc_tx.to_witness_bytes(validated)
        base_size = byte_size(stripped)
        total_size = byte_size(witness_bytes)
        weight = base_size * 3 + total_size
        vsize = ceil(weight / 4)

        Map.merge(base, %{
          validated: true,
          validation_errors: [],
          txid: be_hex(:btc_tx.compute_txid(validated)),
          wtxid: be_hex(:btc_tx.compute_wtxid(validated)),
          base_size: base_size,
          total_size: total_size,
          weight: weight,
          vsize: vsize
        })

      {:error, validation_errors} ->
        base
        |> Map.put(:validated, false)
        |> Map.put(:validation_errors, validation_errors)
    end
  end

  defp extract_inputs(inputs) do
    Enum.map(inputs, fn input ->
      prevout = :btc_tx.get_input_prev_out(input)
      script_sig = :btc_tx.get_input_script_sig(input)
      script_sig_bytes = :btc_tx.get_raw_script_bytes(script_sig)

      %{
        prev_txid_hex: be_hex(:btc_tx.get_prev_out_txid(prevout)),
        prev_vout: :btc_tx.get_prev_out_vout(prevout),
        sequence: :btc_tx.get_input_sequence(input),
        script_sig_hex: Base.encode16(script_sig_bytes, case: :lower),
        script_sig_length: :btc_tx.get_script_length(script_sig)
      }
    end)
  end

  defp extract_outputs(outputs) do
    Enum.map(outputs, fn output ->
      script_pubkey = :btc_tx.get_output_script_pubkey(output)
      script_pubkey_bytes = :btc_tx.get_raw_script_bytes(script_pubkey)
      value_sats = :btc_tx.get_output_value(output)

      %{
        value_sats: value_sats,
        script_type: :btc_tx.classify_output_script(script_pubkey),
        script_pubkey_hex: Base.encode16(script_pubkey_bytes, case: :lower),
        script_pubkey_length: :btc_tx.get_script_length(script_pubkey)
      }
    end)
  end

  defp extract_witnesses(_tx, false), do: []

  defp extract_witnesses(tx, true) do
    case :btc_tx.get_witnesses(tx) do
      {:error, nil} ->
        []

      {:ok, stacks} ->
        Enum.map(stacks, fn stack ->
          items = :btc_tx.get_witness_items(stack)

          Enum.with_index(items, fn item, index ->
            %{
              index: index,
              item_hex: Base.encode16(:btc_tx.get_witness_item_bytes(item), case: :lower)
            }
          end)
        end)
    end
  end

  # Reverse a 32-byte little-endian binary and encode as lowercase hex,
  # producing the conventional big-endian txid display format.
  defp be_hex(le_bytes) do
    le_bytes
    |> :binary.bin_to_list()
    |> Enum.reverse()
    |> :binary.list_to_bin()
    |> Base.encode16(case: :lower)
  end
end
