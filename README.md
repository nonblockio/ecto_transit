# EctoTransit

[![Hex.pm version](https://img.shields.io/hexpm/v/ecto_transit.svg?style=flat)](https://hex.pm/packages/ecto_transit)
[![Hex.pm downloads](https://img.shields.io/hexpm/dt/ecto_transit.svg?style=flat)](https://hex.pm/packages/ecto_transit)
[![CircleCI](https://circleci.com/gh/nonblockio/ecto_transit.svg?style=svg)](https://circleci.com/gh/nonblockio/ecto_transit)

EctoTransit is a transition validator for Ecto and EctoEnum

## Installation

Add `ecto_transit` in your `mix.exs` and run `mix deps.get`

```elixir
def deps do
  [
    {:ecto_transit, "~> 0.1.0"}
  ]
end
```

## How to use

### Generate validator

```elixir
defmodule TODO do
  @states ~w(created scheduled doing overdued done closed)a

  @transitions %{
    :* => :closed,
    :created => ~w(scheduled doing)a,
    :scheduled => ~w(doing overdued)a,
    :doing => ~w(created scheduled done)a
  }

  use EctoTransit, on: @states, rules: @transitions
end

iex> TODO.can_transit?(:created, :scheduled)
true

iex> TODO.can_transit?(:closed, :created)
false
```

### Change validator name

Set `:with` to change validator name

```elixir
use EctoTransit, on: @states, rules: @transitions, with: :should_change?

iex> TODO.should_change?(:created, :scheduled)
true
```

### Integration with EctoEnum

```elixir
defmodule Order do
  import EctoEnum
  defenum State, ~w(created paid in_deliver done)

  @transitions %{
    ~w(created paid in_deliver)a => :done,
    :created => :paid,
    :paid => :in_deliver
  }

  use EctoTransit, on: State, rules: @transitions, with: :can_continue?
end
```

### Validate changset

```elixir
defmodule Order do
  import EctoEnum
  defenum State, ~w(created paid in_deliver done)

  @transitions %{
    ~w(created paid in_deliver)a => :done,
    :created => :paid,
    :paid => :in_deliver
  }

  use EctoTransit, on: State, rules: @transitions, with: :can_continue?

  use Ecto.Schema

  schema "orders" do
    field :state, State
  end
end

iex> order_changeset |> unsafe_validate_transit(:state)
```

### Validate safely

Use lock mechanism to validate safely

```elixir
changeset
|> unsafe_validate_transit(:state)
|> Ecto.Changeset.optimistic_lock(:lock_version)
# raise if concurrent update happens
```


### Use other validator

Set `:with` to change validator

```elixir
%Post{}
|> Ecto.Changeset.change()
|> unsafe_validate_transit(:state, with: :should_change?)
## Post.should_change?(from, to)
```

```elixir
unsafe_validate_transit(:state, with: fn changeset, {from, to} ->
    get_field(changeset, :receive_count) == 0 &&
      match?({:sent, :recalled}, {from, to})
  end
end)
```

```elixir
unsafe_validate_transit(:state, {Audit, :can_change?, [:update, %{context: nil}]})
## Audit.can_change?(changeset, {from, to}, :update, %{context: nil})
```

## FAQ

### How to do callback

EctoTransit does not support callbacks like other libs do. The reason callbacks are needed is in OOP ORM frameworks state and change are sealed inside. So to callbacks are useful when you wanna to check or react. But in Ecto, those information are stored directly in a changeset unconcealed.

Just add more validators you could do checking(before).For reaction, db transaction is more explicit and good for maintenance(after).

### Validator fail when no change on field

`EctoTransit.unsafe_validate_transit/3` requires change happens by default in case other fields change leaving state untouched, which may break state contracts.

So transition validator should not be cuddled with other normal update validator. Or add `require: false` to skip no change checking if you really know what you are doing.
