defmodule Mix.Tasks.Fix do
  @moduledoc """
  Fix the warnings, make compiler happy
  
  # Usage
  mix fix [--force] [--dry-run] [--only vars,aliases,...] [--exclude "file*globs*to*exclude"] [--include "file*glob-white-list"] [--input-file command.set] [--output-file command.set.output]
  
  ## Example
  
  
  1. Everything not in this subfolder will be ignored because out first --(include/exclude) argument was an include.
  ```
  mix fix --include "lib/new_framework/**"
  ```
  
  2.
  The last include/exclude line has the highest precedence. So in this case we will patch lib/new_framework/module/**,
  while ignoring everything else in lib/new_framework, lib/old_framework, lib_/older_fremework. Because the first command was an exclude
  something lib lib/other_module would still be patched in this case.
  
  ```
  mix fix --exclude "lib/new_framework/**" --include "lib/new_framework/module/**" --exclude "lib/old_frameework/**,lib/older_framework**"
  ```
  
  3. Do a dry run to see what would get patched and save the list of items to a file so the can be executed if they look good.
  ```
  mix fix --dry-run --output-file fix.run
  mix fix --dry-run --input-file fix.run
  mix fix --only vars --input-file fix.run
  ```
  
  # Actions
  * --force - ignore uncommitted changed
  * --dry-run - run by only out putting what would be changed. If set --force is not required if there are active changes.
  * --passive - differential build. no mix clean, build --force.
  * --halt-on-error - raise on unexpected exception
  * --only - specify explicit list of fixes to run (var(s),import(s),alias(ses),function(s)), functions not currently supported
  * --exclude - ignore files matching any of these comma separated globs.
  You must wrap this argument in quotes to avoid actually passing in a raw list of args.
  * --include - white list of globs to update | Multiple exclude,includes will control precedence with last entry overriding earlier entries.
  * --input-file - run list of fixes from file
  * --output-file - instead of at once, save set of commands to file for review/edit. Do not actually apply updates.
  """
  
  use Mix.Task
  
  
  @doc """
  Main Entry Points.
  usage: mix fix [--force] [--dry-run] [--only vars,aliases,...] [--exclude "file*globs*to*exclude"] [--include "file*glob-white-list"] [--run-file command.set] [--to-file command.set.output]]
  """
  def run(args) do
    with {:ok, options} <- prepare_options(args),
         :ok <- local_change_check(options),
         :ok <- ExFixer.execute(options) do
      :ok
    else
      {:error, v} -> throw v
      e -> raise {:error, {:unhandle_state, e}}
    end
  end
  
  
  @supported_fixes %{
    "var" => :vars, "vars" => :vars,
    "import" => :imports, "imports" => :imports,
    "attribute" => :attributes, "attributes" => :attributes,
    "alias" => :aliases, "aliases" => :aliases,
    "function" => :functions, "functions" => :functions,
    "other" => :other
  }
  
  @allowed_switches  [
    force: :boolean, dry_run: :boolean,
    passive: :boolean, halt_on_error: :boolean,
    only: :keep, exclude: :keep, include: :keep,
    input_file: :string, output_file: :string,
  ]
  
  
  defp local_change_check(options) do
    with false <- (options[:force] || options[:dry_run] || options[:output_file] || false) && :ok,
         {output, 0} <- System.cmd("git", ["status", "--short"], stderr_to_stdout: true),
         true <- ( (String.trim(output)  == "") || {:error, {:local_change_check, output}})  do
      :ok
    else
      :ok -> :ok
      {:error, {:local_change_check,_}} -> {:error, "Please commit or stash your changes before executing this command"}
      {:error, e} -> {:error, e}
      e -> {:error, "Unexpected failure Checking for Local Changes  [#{inspect e, limit: :infinity}]"}
    end
  end
  
  defp prepare_options(args) do
    with {opts, [], []} <- OptionParser.parse(args, strict: @allowed_switches) do
      initial = Enum.map(@allowed_switches, &({elem(&1,0), nil}))
                |> Map.new()
                |> put_in([:filters], nil)
                |> put_in([:request], Enum.join(args, " "))
                |> put_in([:request_time], DateTime.utc_now())
      options = Enum.reduce(opts, initial, fn({arg,value}, acc) ->
        case arg do
          v when v in[:force, :dry_run, :passive, :input_file, :output_file] -> put_in(acc, [arg], value)
          :only ->
            update_in(acc, [:only], fn(arg) ->
              arg = arg || MapSet.new([])
              add_feature = @supported_fixes[value] || :unsupported
              MapSet.put(arg, add_feature)
            end)
          :exclude -> update_in(acc, [:filters], &( [{:exclude, expand_glob(value)}] ++ (&1 || [])))
          :include -> update_in(acc, [:filters], &( [{:include, expand_glob(value)}] ++ (&1 || [{:exclude, :all}])))
          _ -> acc
        end
      end)
      {:ok, options}
    else
      {_,[],invalid} -> {:error, "Can't recognize following switches: #{inspect(invalid)}\n @see mix fix help"}
      _ -> {:error, "unknown error encountered"}
    end
  end
  
  defp expand_glob(glob) do
    Enum.map(Regex.split( ~r/(?<!\\),/, glob),
      fn(g) ->
        g |> Path.wildcard() |> Enum.map(fn(f) ->
          f |> Path.expand() |> Path.relative_to_cwd()
        end)
      end) |> List.flatten() |> MapSet.new()
  end

end
