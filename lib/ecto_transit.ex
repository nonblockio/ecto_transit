defmodule EctoTransit do
  import Ecto.Changeset

  @default_validator :can_transit?
  @default_message ~s(cannot transit from %{old} to %{new})

  defmacro __using__(opts) do
    quote bind_quoted: [
            states: opts[:on],
            transitions: opts[:rules],
            validator: opts[:with] || @default_validator
          ] do
      import EctoTransit

      parse_transitions(states, transitions)
      |> Enum.each(fn {from, to} ->
        def unquote(validator)(unquote(from), unquote(to)), do: true
      end)

      def unquote(validator)(_, _), do: false
    end
  end

  @spec unsafe_validate_transit(Ecto.Changeset.t(), atom, keyword) :: Ecto.Changeset.t()
  def unsafe_validate_transit(%Ecto.Changeset{} = changeset, field, opts \\ []) do
    required = Keyword.get(opts, :required, true)
    message = Keyword.get(opts, :message, @default_message)
    validator = Keyword.get(opts, :with, @default_validator)

    has_change = match?({:ok, _}, fetch_change(changeset, field))

    ## when has_change is false, get_field fallbacks to read data
    ## so we can check can_transit?(state, state)
    new = changeset |> get_field(field)
    old = changeset.data |> Map.get(field)

    check = fn ->
      if can_transit?(changeset, {old, new}, validator) do
        changeset
      else
        changeset |> add_error(field, message, old: old, new: new)
      end
    end

    case [has_change, required] do
      [true, _] -> check.()
      [false, true] -> check.()
      [false, false] -> changeset
    end
  end

  @doc false
  def parse_transitions(states, transitions) do
    transitions
    |> Enum.map(fn {from, to} ->
      for from <- List.wrap(from), to <- List.wrap(to) do
        expand_transition(states, from, to)
      end
    end)
    |> List.flatten()
    |> Enum.uniq()
  end

  defp can_transit?(changeset, {from, to}, func) when is_atom(func) do
    apply(changeset.data.__struct__, func, [from, to])
  end

  defp can_transit?(changeset, {from, to}, func) when is_function(func, 2) do
    apply(func, [changeset, {from, to}])
  end

  defp can_transit?(changeset, {from, to}, {mod, func, ex_args}) do
    apply(mod, func, [changeset, {from, to} | ex_args])
  end

  defp expand_transition(states, from, to) when is_list(states),
    do: expand_list_transition(states, from, to)

  defp expand_transition(states, from, to) when is_atom(states) do
    if Code.ensure_compiled?(EctoEnum) and
         function_exported?(states, :__enum_map__, 0) and
         function_exported?(states, :valid_value?, 1) do
      expand_enum_transition(states, from, to)
    else
      raise "cannot create transition validator on module #{states}, expected an EctoEnum"
    end
  end

  defp expand_list_transition(list, from, :*) do
    for to <- list do
      expand_list_transition(list, from, to)
    end
  end

  defp expand_list_transition(list, :*, to) do
    for from <- list do
      expand_list_transition(list, from, to)
    end
  end

  defp expand_list_transition(list, from, to) do
    if [from, to] |> Enum.all?(&Kernel.in(&1, list)) do
      {from, to}
    else
      raise "unknown transition state in #{inspect(from)} => #{inspect(to)}"
    end
  end

  defp expand_enum_transition(enum, from, :*) do
    for to <- Keyword.keys(enum.__enum_map__) do
      expand_enum_transition(enum, from, to)
    end
  end

  defp expand_enum_transition(enum, :*, to) do
    for from <- Keyword.keys(enum.__enum_map__) do
      expand_enum_transition(enum, from, to)
    end
  end

  defp expand_enum_transition(enum, from, to) when is_atom(from) and is_atom(to) do
    case [from, to] |> Enum.map(&enum.valid_value?/1) do
      [true, true] ->
        [
          {from, to},
          {enum.__enum_map__[from], to},
          {from, enum.__enum_map__[to]},
          {enum.__enum_map__[from], enum.__enum_map__[to]}
        ]

      _ ->
        raise "unknown transition state in #{inspect(from)} => #{inspect(to)}"
    end
  end

  defp expand_enum_transition(_enum, from, to) do
    raise "invalid transition state, expected an Atom, in: #{inspect(from)} => #{inspect(to)}"
  end
end
