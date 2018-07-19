# Fixer

Fix compiler warnings automatically:

* Remove unused aliases
* Prefix unused variables

## Installation

Add the following lines to `deps()` in `mix.exs`:

```elixir
    {:ex_fixer, "~> 1.0.0", only: :dev},
```

## Usage

```
mix fix
```

