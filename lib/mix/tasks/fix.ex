defmodule Mix.Tasks.Fix do
  use Mix.Task

  @shortdoc "Fix the warnings, make compiler happy"

  def run(args) do
    {opts, [], invalid} =
      OptionParser.parse(
        args,
        strict: [
          force: :boolean
        ]
      )

    if length(invalid) > 0, do: raise("Can't recognize switches: #{inspect(invalid)}")

    if !opts[:force] do
      {output, 0} = System.cmd("git", ["status", "--short"], stderr_to_stdout: true)

      if output |> String.trim() |> String.length() > 0,
        do: raise("Please commit or stash your changes before executing this command")
    end

    ExFixer.execute()
  end
end
