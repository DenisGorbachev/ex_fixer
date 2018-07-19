# Fixer

Fix compiler warnings automatically:

* Prefix unused variables
* Remove unused aliases
* Remove unused imports

## Installation

Add the following lines to `deps()` in `mix.exs`:

```elixir
    {:ex_fixer, "~> 1.0.0", only: :dev},
```

## Usage

```
mix fix
```

