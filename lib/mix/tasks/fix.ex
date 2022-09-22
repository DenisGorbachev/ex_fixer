defmodule Mix.Tasks.Fix do
  use Mix.Task

  @doc """
  Fix the warnings, make compiler happy
  
  # Usage
  mix fix [--force] [--only vars,aliases,...] [--exclude "file*globs*to*exclude"] [--include "file*glob-white-list"] [--run-file command.set] [--to-file command.set.output] [--dry-run]
  
  # Actions
  * --force - ignore uncommitted changed
  * --only - specify explicit list of fixes to run
  * --exclude - ignore files matching any of these comma separated globs.
  * --include - white list of globs to update | Multiple exclude,includes will control precedence with last entry overriding earlier entries.
  * --from-file - run list of fixes from file
  * --output-file - instead of at once, save set of commands to file for review/edit.
  * --dry-run - run by only out putting what would be changed. If set --force is not required if there are active changes.
  """
  def run(args) do
    {opts, [], invalid} =
      OptionParser.parse(
        args,
        strict: [
          force: :boolean,
          dry_run: :boolean,
          only: :keep,
          exclude: :keep,
          include: :keep,
          from_file: :string,
          output_file: :string,
        ]
      )
      
    if length(invalid) > 0, do: raise("Can't recognize switches: #{inspect(invalid)}")

    request = Enum.join(args, " ")
    options = Enum.reduce(opts, %{request: request}, fn({arg,value}, acc) ->
      case arg do
        :force -> put_in(acc, [:force], value)
        :dry_run -> put_in(acc, [:dry_run], value)
        :only -> update_in(acc, [:only], &(MapSet.put(&1 || MapSet.new([]), value)))
        :exclude -> update_in(acc, [:filters], &( [{:exclude, expand_glob(value)}] ++ (&1 || [])))
        :include -> update_in(acc, [:filters], &( [{:include, expand_glob(value)}] ++ (&1 || [{:exclude, :all}])))
        :from_file -> put_in(acc, [:from_file], value)
        :output_file -> put_in(acc, [:output_file], value)
      end
    end)
    
    if !options[:force] && !options[:dry_run] && !options[:output_file] do
      {output, 0} = System.cmd("git", ["status", "--short"], stderr_to_stdout: true)

      if output |> String.trim() |> String.length() > 0,
        do: raise("Please commit or stash your changes before executing this command")
    end

    ExFixer.execute(options)
  end
  
  defp expand_glob(glob) do
    Enum.map(String.split(glob, ","), fn(g) ->
      g
      |> Path.wildcard()
      |> Enum.map(fn(f) ->
        f
        |> Path.expand()
        |> Path.relative_to_cwd()
      end)
    end)|> List.flatten() |> MapSet.new()
  end

end
