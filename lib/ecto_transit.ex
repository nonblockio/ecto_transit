defmodule EctoTransit do
  @moduledoc """
  Defines transition rules.

  When used, the transit expects the `:on` and `:rules` as option. The `:on` should
  be a list of avaliable states or an `EctoEnum` module, and `:rules` should be a map with transition rules.
  You can use state, list of states or wildcard `:*` in rules.
  Optional option `:with` could be used to change generated function name (default `:can_transit?`).
  It will be handy if you defines two transitions in one module.

  States can be any types, though examples are all atom.

      iex> defmodule TODO do
      ...>   @states ~w(created scheduled doing overdued done closed)a
      ...>
      ...>   @transitions %{
      ...>     :* => :closed,
      ...>     :created => ~w(scheduled doing)a,
      ...>     :scheduled => ~w(doing overdued)a,
      ...>     :doing => ~w(created scheduled done)a
      ...>   }
      ...>
      ...>   use EctoTransit, on: @states, rules: @transitions
      ...> end
      iex> TODO.can_transit?(nil, :created)
      false
      iex> TODO.can_transit?(:scheduled, :overdued)
      true
      iex> TODO.can_transit?(:unknown, :closed)
      false

  ## Use with `EctoEnum`

    `EctoTransit` is designed for compatibility with `EctoEnum`, while it works well alone.

    Option `:on` can accept an enum module defined by `EctoEnum`,

      iex> defmodule Order do
      ...>   import EctoEnum
      ...>   defenum State, ~w(created paid in_deliver done)
      ...>
      ...>   @transitions %{
      ...>     ~w(created paid in_deliver)a => :done,
      ...>     :created => :paid,
      ...>     :paid => :in_deliver
      ...>   }
      ...>
      ...>   use EctoTransit, on: State, rules: @transitions, with: :can_continue?
      ...> end
      iex> Order.can_continue?(:created, :paid)
      true
      iex> Order.can_continue?(:paid, "in_deliver")
      true
  """

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

  @doc """
  Validate the change on given field follows transition rules.

  This function cannot guarantee transition consistency in concurrency updates thus marked as unsafe.
  For example, if an change is committed when an check is passed, the follow update
  might break transition rules, considering an update action of ecto is not conditional.

  Extra lock mechanism is required if you want to ensure consistency.
  See `Ecto.Query.lock/2` or `Ecto.Changeset.optimistic_lock/3`.

  ## Options
    * `:message` - the message on failure, defaults to "cannot transit from %{old} to %{new}"
    * `:required` - if the change on the field is required, defaults to true
    * `:with` - the function to validate transitions, defaults to :can_transit?.
      function `fun` can be one of:
      * atom - called as `apply(mod, fun, [old, new])`, which `mod` is the module that defines the schama of changeset
      * capture or anonymous function - called as `apply(fun, [changeset, {old, new}])`
      * {mod, fun, ex_args} - called as `apply(mod, fun, [changeset, {old, new} | ex_args])`

      When `required` is true (by default), `old` and `new` could be the same, meaning there's no change on given field.

  ## Examples

    use defualt `:can_transit?/2`:

      changeset |> unsafe_validate_transit(:state)
      changeset |> unsafe_validate_transit(:state, message: "%{old} -> %{new} is forbidden")

    use `required: false` to skip check if no change:

      %Post{state: :published}
      |> change() ## no change
      |> unsafe_validate_transit(:state, required: false) ## skip check

    use `Post.can_close?/2`:

      %Post{state: :published}
      |> change(state: :closed)
      |> unsafe_validate_transit(:state, with: :can_close?)

    use anonymous function like hook:

      recall_message_changeset
      |> unsafe_validate_transit :state, with: fn changeset, {from, to} ->
          get_field(changeset, :receive_count) == 0 && match?({:sent, :recalled}, {from, to})
        end
      end

    use `Audit.can_change?(changeset, {from, to}, action, metadata)`:

      sensitive_changeset
      |> unsafe_validate_transit(:state, {Audit, :can_change?, [:update, %{context: nil}]})

    use `Ecto.Query.optimistic_lock/3` to ensure consistency:

      changeset
      |> unsafe_validate_transit(:state)
      |> optimistic_lock(:lock_version) # raise if concurrent update happens
  """

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
