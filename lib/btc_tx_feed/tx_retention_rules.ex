defmodule BtcTxFeed.TxRetentionRules do
  @moduledoc """
  Declarative DSL for matching transaction `details_map` values produced by
  `BtcTxFeed.TxParser.parse/1`.

  Rules are plain Elixir data — no runtime code evaluation.

  ## Boolean composition

      {:all, [rule, ...]}         — every child rule must match
      {:any, [rule, ...]}         — at least one child rule must match
      {:not, rule}                — negate a child rule

  ## Scalar comparisons

  Target any of the scalar fields listed in `@scalar_fields`.

      {:eq,      field, value}
      {:neq,     field, value}
      {:gt,      field, value}
      {:gte,     field, value}
      {:lt,      field, value}
      {:lte,     field, value}
      {:between, field, min, max}
      {:in,      field, values}

  ## Domain-specific predicates

      {:has_output_script_type,        type}
      {:output_script_type_count_gte,  type, n}
      {:has_any_output_script_type,    [type, ...]}
      {:any_input_witness_items_eq,    n}
      {:any_input_witness_items_gte,   n}
      {:witness_total_items_gte,       n}
      {:witness_total_bytes_gte,       n}
      {:largest_witness_item_bytes_gte, n}
  """

  # Fields from details_map that scalar comparison operators may target.
  @scalar_fields MapSet.new([
                   :version,
                   :is_segwit,
                   :lock_time,
                   :has_coinbase_marker,
                   :validated,
                   :input_count,
                   :output_count,
                   :base_size,
                   :total_size,
                   :weight,
                   :vsize,
                   # Output script summary fields
                   :has_op_return,
                   :op_return_output_count,
                   :has_non_standard_output,
                   # Witness summary fields
                   :witness_total_items,
                   :witness_total_bytes,
                   :largest_witness_item_bytes,
                   :inputs_with_witness_count
                 ])

  # ---------------------------------------------------------------------------
  # API
  # ---------------------------------------------------------------------------

  @doc """
  Validates the structure of a rule without evaluating it against any
  transaction. Returns `:ok` or `{:error, reason}`.
  """
  def validate_rule(rule) do
    case do_validate(rule) do
      :ok -> :ok
      {:error, _} = err -> err
    end
  end

  @doc """
  Returns `true` if `details` (a map produced by `TxParser.parse/1`) matches
  `rule`. Does not validate `rule` — callers are responsible for ensuring the
  rule is structurally valid. Use `match!/2` if you want validation with a
  raised `ArgumentError` on invalid rules.
  """
  def match?(details, rule) do
    do_match(details, rule)
  end

  @doc """
  Same as `match?/2` but validates `rule` first and raises `ArgumentError` if
  the rule is structurally invalid.
  """
  def match!(details, rule) do
    case validate_rule(rule) do
      :ok -> do_match(details, rule)
      {:error, reason} -> raise ArgumentError, reason
    end
  end

  # ---------------------------------------------------------------------------
  # Validation
  # ---------------------------------------------------------------------------

  defp do_validate({:all, children}) when is_list(children) and children != [] do
    validate_children(children)
  end

  defp do_validate({:all, []}) do
    {:error, ":all requires at least one child rule"}
  end

  defp do_validate({:all, _}) do
    {:error, ":all second element must be a list"}
  end

  defp do_validate({:any, children}) when is_list(children) and children != [] do
    validate_children(children)
  end

  defp do_validate({:any, []}) do
    {:error, ":any requires at least one child rule"}
  end

  defp do_validate({:any, _}) do
    {:error, ":any second element must be a list"}
  end

  defp do_validate({:not, child}) do
    do_validate(child)
  end

  defp do_validate({op, field, value})
       when op in [:gt, :gte, :lt, :lte] do
    if is_number(value) do
      validate_field(field)
    else
      {:error, "#{op} requires a numeric value, got: #{inspect(value)}"}
    end
  end

  defp do_validate({op, field, _value})
       when op in [:eq, :neq] do
    validate_field(field)
  end

  defp do_validate({:between, field, min, max}) when is_number(min) and is_number(max) do
    if min <= max do
      validate_field(field)
    else
      {:error, ":between min (#{min}) must be <= max (#{max})"}
    end
  end

  defp do_validate({:between, _field, min, max}) do
    bad = if not is_number(min), do: min, else: max
    {:error, ":between requires numeric min and max, got: #{inspect(bad)}"}
  end

  defp do_validate({:in, field, values}) when is_list(values) do
    validate_field(field)
  end

  defp do_validate({:in, _field, _}) do
    {:error, ":in values must be a list"}
  end

  defp do_validate({:has_output_script_type, _type}) do
    :ok
  end

  defp do_validate({:output_script_type_count_gte, _type, n}) when is_integer(n) do
    :ok
  end

  defp do_validate({:has_any_output_script_type, types}) when is_list(types) and types != [] do
    :ok
  end

  defp do_validate({:has_any_output_script_type, _}) do
    {:error, ":has_any_output_script_type requires a non-empty list of types"}
  end

  defp do_validate({:any_input_witness_items_eq, n}) when is_integer(n) do
    :ok
  end

  defp do_validate({:any_input_witness_items_gte, n}) when is_integer(n) do
    :ok
  end

  defp do_validate({:witness_total_items_gte, n}) when is_integer(n) do
    :ok
  end

  defp do_validate({:witness_total_bytes_gte, n}) when is_integer(n) do
    :ok
  end

  defp do_validate({:largest_witness_item_bytes_gte, n}) when is_integer(n) do
    :ok
  end

  defp do_validate({op}) do
    {:error, "malformed rule: #{inspect({op})} — missing required arguments"}
  end

  defp do_validate({op, _}) when op in [:eq, :neq, :gt, :gte, :lt, :lte] do
    {:error, "malformed rule: #{inspect(op)} requires a field and a value"}
  end

  defp do_validate({op, _}) when op in [:has_output_script_type] do
    {:error, "malformed rule: #{inspect(op)} requires a type argument"}
  end

  defp do_validate(rule) do
    {:error, "unknown or malformed rule: #{inspect(rule)}"}
  end

  defp validate_field(field) do
    if MapSet.member?(@scalar_fields, field) do
      :ok
    else
      {:error, "unsupported field: #{inspect(field)}"}
    end
  end

  defp validate_children(children) do
    Enum.reduce_while(children, :ok, fn child, :ok ->
      case do_validate(child) do
        :ok -> {:cont, :ok}
        err -> {:halt, err}
      end
    end)
  end

  # ---------------------------------------------------------------------------
  # Evaluation
  # ---------------------------------------------------------------------------

  defp do_match(details, {:all, children}) do
    Enum.all?(children, &do_match(details, &1))
  end

  defp do_match(details, {:any, children}) do
    Enum.any?(children, &do_match(details, &1))
  end

  defp do_match(details, {:not, child}) do
    not do_match(details, child)
  end

  defp do_match(details, {:eq, field, value}) do
    Map.get(details, field) == value
  end

  defp do_match(details, {:neq, field, value}) do
    Map.get(details, field) != value
  end

  defp do_match(details, {:gt, field, value}) do
    case Map.get(details, field) do
      nil -> false
      v -> v > value
    end
  end

  defp do_match(details, {:gte, field, value}) do
    case Map.get(details, field) do
      nil -> false
      v -> v >= value
    end
  end

  defp do_match(details, {:lt, field, value}) do
    case Map.get(details, field) do
      nil -> false
      v -> v < value
    end
  end

  defp do_match(details, {:lte, field, value}) do
    case Map.get(details, field) do
      nil -> false
      v -> v <= value
    end
  end

  defp do_match(details, {:between, field, min, max}) do
    case Map.get(details, field) do
      nil -> false
      v -> v >= min and v <= max
    end
  end

  defp do_match(details, {:in, field, values}) do
    Map.get(details, field) in values
  end

  defp do_match(details, {:has_output_script_type, type}) do
    Map.has_key?(Map.get(details, :output_script_type_counts, %{}), type)
  end

  defp do_match(details, {:output_script_type_count_gte, type, n}) do
    count = Map.get(Map.get(details, :output_script_type_counts, %{}), type, 0)
    count >= n
  end

  defp do_match(details, {:has_any_output_script_type, types}) do
    counts = Map.get(details, :output_script_type_counts, %{})
    Enum.any?(types, &Map.has_key?(counts, &1))
  end

  defp do_match(details, {:any_input_witness_items_eq, n}) do
    counts = Map.get(details, :witness_item_counts_per_input, [])
    counts != [] and Enum.any?(counts, &(&1 == n))
  end

  defp do_match(details, {:any_input_witness_items_gte, n}) do
    counts = Map.get(details, :witness_item_counts_per_input, [])
    counts != [] and Enum.any?(counts, &(&1 >= n))
  end

  defp do_match(details, {:witness_total_items_gte, n}) do
    Map.get(details, :witness_total_items, 0) >= n
  end

  defp do_match(details, {:witness_total_bytes_gte, n}) do
    Map.get(details, :witness_total_bytes, 0) >= n
  end

  defp do_match(details, {:largest_witness_item_bytes_gte, n}) do
    Map.get(details, :largest_witness_item_bytes, 0) >= n
  end
end
