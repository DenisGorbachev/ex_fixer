# Fixer

Fix compiler warnings automatically:

* Prefix unused variables
* Remove unused aliases
* Remove unused imports

![Fixer](https://raw.githubusercontent.com/DenisGorbachev/ex_fixer/master/img/cover.jpg)

## Installation

Add the following lines to `deps()` in `mix.exs`:

```elixir
    {:ex_fixer, "~> 1.0.0", only: :dev},
```

## Usage

```
mix fix
```

