defmodule ExFixerTest do
  use ExUnit.Case, async: true

  import ExFixer

  setup %{test: test} = params do
    filename = "#{System.tmp_dir!()}/#{Atom.to_string(test)}.fixture.ex"

    File.write!(
      filename,
      ("""
       defmodule Test do
         import CoinHunter.Utils
         import CoinHunter.Simulator, only: [simulate: 4]
         import OK, only: [success: 1, failure: 1]

         alias CoinHunter.Repo
         alias CoinHunter.Model.{Account}
         alias CoinHunter.Model.{Trade, Level, Order}
         alias CoinHunter.Connector

         def execute_for_sample(_sample), do: :noop

         def execute_for_sample(%{symbol: symbol}) do
           [exchange, base, quote] = to_list(symbol)
         end

         def get_trades(symbol) do
           [exchange, base, quote] = to_list(symbol)
           success(trades) = Connector.get_trades(exchange, base, quote)
         end
       end
       """
       |> String.trim()) <> "\n"
    )

    # to update compilation_results:
    # 1. Run the test once
    # 2. Run the following command:
    #    cp /tmp/Elixir.CoinHunter.FixerTest.1.fixture.ex lib/coin_hunter/ && mix compile --force 2>&1 | sed -e 's/lib\/coin_hunter\/Elixir.CoinHunter.FixerTest.1.fixture.ex/#{filename}/g' | less -p '#\{filename\}'; rm lib/coin_hunter/Elixir.CoinHunter.FixerTest.1.fixture.ex
    # 3. Copy the lines with "#{filename}" from output
    compilation_results =
      ("""
       Compiling 5 files (.ex)
       warning: this clause cannot match because a previous clause at line 11 always matches
       #{filename}:13

       warning: variable "base" is unused
       #{filename}:14

       warning: variable "exchange" is unused
       #{filename}:14

       warning: variable "quote" is unused
       #{filename}:14

       warning: variable "trades" is unused
       #{filename}:19

       warning: unused alias Account
       #{filename}:7

       warning: unused alias Level
       #{filename}:8

       warning: unused alias Order
       #{filename}:8

       warning: unused alias Repo
       #{filename}:6

       warning: unused alias Trade
       #{filename}:8

       warning: unused import CoinHunter.Simulator
       #{filename}:3

       warning: unused import OK.failure/1
       #{filename}:4
       """
       |> String.trim()) <> "\n"

    %{filename: filename, compilation_results: compilation_results}
  end
  
  
  def blank_options() do
    %{
      request: "",
      request_time: DateTime.from_unix(12341234),
      force: false,
      dry_run: false,
      passice: false,
      halt_on_error: false,
      only: nil,
      filters: nil,
      input_file: nil,
      output_file: nil
    }
  end

  
  test "warnings", %{filename: filename, compilation_results: compilation_results} do
    warnings = parse_warnings(compilation_results, blank_options())
    assert length(warnings) > 0

    assert Enum.at(warnings, 2) == %{
             file_name: filename,
             item: nil,
             line: "warning: variable \"exchange\" is unused\n/tmp/test warnings.fixture.ex:14\n\n",
             line_number: 14,
             text: "variable \"exchange\" is unused",
             warning_type: :vars
           }
  end

  test "fix", %{filename: filename, compilation_results: compilation_results} do
    execute_for(compilation_results, blank_options())

    assert File.read!(filename) == """
           defmodule Test do
             import CoinHunter.Utils
             import OK, only: [success: 1]

             alias CoinHunter.Connector

             def execute_for_sample(_sample), do: :noop

             def execute_for_sample(%{symbol: symbol}) do
               [_exchange, _base, _quote] = to_list(symbol)
             end

             def get_trades(symbol) do
               [exchange, base, quote] = to_list(symbol)
               success(_trades) = Connector.get_trades(exchange, base, quote)
             end
           end
           """
  end

  test "fix_unused_variable" do
    assert fix_unused_variable("sample", "def execute_for_sample(sample) do", blank_options()) ==
             "def execute_for_sample(_sample) do"

    assert fix_unused_variable("symbol", "def execute_for_sample(%{symbol: symbol}) do", blank_options()) ==
             "def execute_for_sample(%{symbol: _symbol}) do"
  end

  test "fix_unused_atom" do
    assert fix_unused_atom("CoinHunter.Repo", "alias", "alias CoinHunter.Repo", blank_options()) == ""
    assert fix_unused_atom("Account", "alias", "  alias CoinHunter.Model.{Account}", blank_options()) == ""

    assert fix_unused_atom("Trade", "alias", "alias CoinHunter.Model.{Trade, Level, Order}\n", blank_options()) ==
             "alias CoinHunter.Model.{Level, Order}\n"

    assert fix_unused_atom("Level", "alias", "alias CoinHunter.Model.{Trade, Level, Order}\n", blank_options()) ==
             "alias CoinHunter.Model.{Trade, Order}\n"

    assert fix_unused_atom("Order", "alias", "alias CoinHunter.Model.{Trade, Level, Order}\n", blank_options()) ==
             "alias CoinHunter.Model.{Trade, Level}\n"

    assert fix_unused_atom(
             "OK.success/1",
             "import",
             "import OK, only: [success: 1, failure: 1, for: 1]\n", blank_options()
           ) == "import OK, only: [failure: 1, for: 1]\n"

    assert fix_unused_atom(
             "OK.failure/1",
             "import",
             "import OK, only: [success: 1, failure: 1, for: 1]\n", blank_options()
           ) == "import OK, only: [success: 1, for: 1]\n"

    assert fix_unused_atom(
             "OK.for/1",
             "import",
             "import OK, only: [success: 1, failure: 1, for: 1]\n", blank_options()
           ) == "import OK, only: [success: 1, failure: 1]\n"
  end

  @compile [:nowarn_unused_vars, :nowarn_unused_function]
end
