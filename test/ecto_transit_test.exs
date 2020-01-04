defmodule EctoTransitTest do
  use ExUnit.Case
  doctest EctoTransit

  describe "macro" do
    test "with list states" do
      defmodule X do
        @states ~w(created confirmed checked closed cheated queued)

        @transitions %{
          "created" => ["confirmed", "closed"],
          "confirmed" => "checked",
          "checked" => "closed",
          :* => "cheated",
          "queued" => :*
        }

        use EctoTransit, on: @states, rules: @transitions

        def states, do: @states
      end

      assert function_exported?(X, :can_transit?, 2)

      assert X.can_transit?("created", "confirmed")
      assert X.can_transit?("created", "closed")
      assert X.can_transit?("confirmed", "checked")
      assert X.can_transit?("checked", "closed")
      assert X.can_transit?(Enum.random(X.states()), "cheated")

      refute X.can_transit?(nil, nil)
      refute X.can_transit?(Enum.random(X.states()), nil)
      refute X.can_transit?(nil, Enum.random(X.states()))
      refute X.can_transit?(:created, "confirmed")
      refute X.can_transit?(:created, :created)
    end

    test "with EctoEnum" do
      defmodule X do
        import EctoEnum
        defenum(State, ~w(created confirmed checked closed cheated queued))

        @transitions %{
          :created => ~w(confirmed closed)a,
          :confirmed => :checked,
          :checked => :closed,
          :* => :cheated,
          :queued => :*
        }

        use EctoTransit, on: State, rules: @transitions
      end

      assert function_exported?(X, :can_transit?, 2)

      assert X.can_transit?("created", "confirmed")
      assert X.can_transit?(:created, "confirmed")
      assert X.can_transit?("created", "closed")
      assert X.can_transit?("created", :closed)
      assert X.can_transit?("confirmed", "checked")
      assert X.can_transit?(:checked, :closed)
      assert X.can_transit?(Enum.random(X.State.__valid_values__()), "cheated")

      refute X.can_transit?(nil, nil)
      refute X.can_transit?(Enum.random(X.State.__valid_values__()), nil)
      refute X.can_transit?(nil, Enum.random(X.State.__valid_values__()))
      refute X.can_transit?("confirmed", :created)
    end

    test "for two states set" do
      defmodule X do
        use EctoTransit,
          on: ~w(a b c)a,
          with: :can_atom_transit?,
          rules: %{
            :* => :c,
            :a => :*,
            :b => :a
          }

        use EctoTransit,
          on: [1, 2, 3],
          with: :can_integer_transit?,
          rules: %{
            :* => 3,
            1 => :*,
            2 => 1
          }
      end

      assert function_exported?(X, :can_atom_transit?, 2)
      assert function_exported?(X, :can_integer_transit?, 2)
      refute function_exported?(X, :can_transit?, 2)

      assert X.can_atom_transit?(:a, :b)
      refute X.can_atom_transit?(:c, :b)
      refute X.can_atom_transit?(1, 2)

      assert X.can_integer_transit?(1, 2)
      refute X.can_integer_transit?(3, 2)
      refute X.can_integer_transit?(:a, :b)
    end

    test "with unknown state" do
      schema = ~s"""
      defmodule X do
        @states ~w(created confirmed checked closed cheated queued)

        @transitions %{
          "created" => ["confirmed", "closed"],
          "confirmed" => "checked",
          "checked" => "closed",
          :* => "cheated",
          "queued" => :*,
          "unknown" => "created"
        }

        use EctoTransit, on: @states, rules: @transitions

        def states, do: @states
      end
      """

      error = catch_error(Code.compile_string(schema))
      assert error.message == ~s(unknown transition state in "unknown" => "created")
    end

    test "with unknown EctoEnum state" do
      schema = ~s"""
      defmodule X do
        import EctoEnum
        defenum(State, ~w(created confirmed checked closed cheated queued))

        @transitions %{
          :created => ~w(confirmed closed)a,
          :confirmed => :checked,
          :checked => :closed,
          :* => :cheated,
          :queued => :*,
          :unknown => :created
        }

        use EctoTransit, on: State, rules: @transitions
      end
      """

      error = catch_error(Code.compile_string(schema))
      assert error.message == ~s(unknown transition state in :unknown => :created)
    end

    test "with non-atom EctoEnum state" do
      schema = ~s"""
      defmodule X do
        import EctoEnum
        defenum(State, ~w(created confirmed checked closed cheated queued))

        @transitions %{
          :created => ~w(confirmed closed)a,
          :confirmed => :checked,
          "checked" => :closed,
          :* => :cheated,
          :queued => :*
        }

        use EctoTransit, on: State, rules: @transitions
      end
      """

      error = catch_error(Code.compile_string(schema))

      assert error.message ==
               ~s(invalid transition state, expected an Atom, in: "checked" => :closed)
    end

    test "with non-EctoEnum module state" do
      schema = ~s"""
      defmodule X do
        use Ecto.Schema

        @transitions %{
          :created => ~w(confirmed closed)a,
          :confirmed => :checked,
          :checked => :closed,
          :* => :cheated,
          :queued => :*
        }

        use EctoTransit, on: State, rules: @transitions
      end
      """

      error = catch_error(Code.compile_string(schema))

      assert error.message ==
               "cannot create transition validator on module Elixir.State, expected an EctoEnum"
    end
  end

  describe "validator" do
    import EctoTransit

    setup do
      defmodule X do
        use Ecto.Schema

        import EctoEnum
        defenum(State, ~w(created confirmed checked closed cheated queued))

        @transitions %{
          :created => ~w(confirmed closed)a,
          :confirmed => :checked,
          :checked => :closed,
          :* => :cheated,
          :queued => :*
        }

        use EctoTransit, on: State, rules: @transitions

        schema "xs" do
          field(:state, State)
        end

        def validator_true(_changeset, {:unknown, :undefined}, :ex_arg1, ex_arg2)
            when is_tuple(ex_arg2),
            do: true

        def validator_false(_changeset, {:unknown, :undefined}, :ex_arg1, ex_arg2)
            when is_tuple(ex_arg2),
            do: false
      end

      {:ok, schema: X}
    end

    test "when ok", context do
      schema = context[:schema]

      {old, new} = {:queued, "checked"}
      assert schema.can_transit?(old, new)
      changeset = make_change(schema, :state, {old, new}) |> unsafe_validate_transit(:state)
      assert changeset.valid?
    end

    test "when change not required", context do
      schema = context[:schema]

      changeset =
        schema.__struct__(%{state: :confirmed})
        |> Ecto.Changeset.change()
        |> unsafe_validate_transit(:state, required: false)

      assert changeset.valid?
    end

    test "when change required", context do
      schema = context[:schema]

      changeset =
        schema.__struct__(%{state: :confirmed})
        |> Ecto.Changeset.change()
        |> unsafe_validate_transit(:state)

      refute changeset.valid?
    end

    test "with no change", context do
      schema = context[:schema]

      {old, new} = {:confirmed, :confirmed}
      refute schema.can_transit?(old, new)
      changeset = make_change(schema, :state, {old, new}) |> unsafe_validate_transit(:state)
      refute changeset.valid?
      assert %{state: ["cannot transit from :confirmed to :confirmed"]} = errors_on(changeset)
    end

    test "with nil begin state", context do
      schema = context[:schema]

      {old, new} = {nil, :checked}
      refute schema.can_transit?(old, new)
      changeset = make_change(schema, :state, {old, new}) |> unsafe_validate_transit(:state)
      refute changeset.valid?
      assert %{state: ["cannot transit from nil to :checked"]} = errors_on(changeset)
    end

    test "with nil end state", context do
      schema = context[:schema]

      {old, new} = {:checked, nil}
      refute schema.can_transit?(old, new)
      changeset = make_change(schema, :state, {old, new}) |> unsafe_validate_transit(:state)
      refute changeset.valid?
      assert %{state: ["cannot transit from :checked to nil"]} = errors_on(changeset)
    end

    test "with unexpected transition", context do
      schema = context[:schema]

      {old, new} = {:checked, "created"}
      refute schema.can_transit?(old, new)
      changeset = make_change(schema, :state, {old, new}) |> unsafe_validate_transit(:state)
      refute changeset.valid?
    end

    test "with atom validator", context do
      schema = context[:schema]

      {old, new} = {:queued, "checked"}
      assert schema.can_transit?(old, new)

      changeset =
        make_change(schema, :state, {old, new})
        |> unsafe_validate_transit(:state, with: :can_transit?)

      assert changeset.valid?
    end

    test "with atom validator and unexpected transition", context do
      schema = context[:schema]

      {old, new} = {:checked, "created"}
      refute schema.can_transit?(old, new)

      changeset =
        make_change(schema, :state, {old, new})
        |> unsafe_validate_transit(:state, with: :can_transit?)

      refute changeset.valid?
    end

    test "with anonymous function", context do
      schema = context[:schema]

      {old, new} = {:unknown, :undefined}

      changeset = make_change(schema, :state, {old, new})

      changeset =
        changeset
        |> unsafe_validate_transit(:state, with: fn ^changeset, {^old, ^new} -> true end)

      assert changeset.valid?
    end

    test "with anonymous function and unexpected transition", context do
      schema = context[:schema]

      {old, new} = {:unknown, :undefined}

      changeset = make_change(schema, :state, {old, new})

      changeset =
        changeset
        |> unsafe_validate_transit(:state, with: fn ^changeset, {^old, ^new} -> false end)

      refute changeset.valid?
    end

    test "with MFA", context do
      schema = context[:schema]

      {old, new} = {:unknown, :undefined}

      changeset =
        make_change(schema, :state, {old, new})
        |> unsafe_validate_transit(:state, with: {schema, :validator_true, [:ex_arg1, {:etc}]})

      assert changeset.valid?
    end

    test "with MFA and unexpected transition", context do
      schema = context[:schema]

      {old, new} = {:unknown, :undefined}

      changeset =
        make_change(schema, :state, {old, new})
        |> unsafe_validate_transit(:state, with: {schema, :validator_false, [:ex_arg1, {:etc}]})

      refute changeset.valid?
    end

    test "with message", context do
      schema = context[:schema]

      {old, new} = {:checked, "created"}
      refute schema.can_transit?(old, new)
      changeset = make_change(schema, :state, {old, new}) |> unsafe_validate_transit(:state)
      refute changeset.valid?
      assert %{state: [~s(cannot transit from :checked to "created")]} = errors_on(changeset)
    end

    test "with user-defined message", context do
      schema = context[:schema]
      {old, new} = {:checked, "created"}

      changeset =
        make_change(schema, :state, {old, new})
        |> unsafe_validate_transit(:state, message: "%{old} => %{new} is forbidden")

      refute changeset.valid?
      assert %{state: [~s(:checked => "created" is forbidden)]} = errors_on(changeset)
    end
  end

  defp make_change(schema, field, {old, new}) do
    schema.__struct__(%{field => old})
    |> Ecto.Changeset.change(%{field => new})
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> inspect()
      end)
    end)
  end
end
