defmodule ExFixer do
  
  @warning_type_regex %{
    vars: ~r/variable "(?<variable>[^\"]+)" is unused/,
    attributes: ~r/module attribute @(?<atom>[^\s]+) was set but never used/,
    imports: ~r/unused import (?<atom>.+)/,
    aliases: ~r/unused alias (?<atom>.+)/,
  }
  
  def execute(options) do
    with {:ok, warnings} <- warning_set(options) do
      execute_for(warnings, options)
    else
      error -> error
    end
  end
  
  def warning_set(options) do
    cond do
      replay = options[:intput_file] -> File.read(replay)
      :else -> compilation_results(options)
    end
  end

  def execute_for(compilation_results, options) do
    compilation_results
    |> parse_warnings(options)
    |> Enum.group_by(&(&1.file_name))
    |> apply_filters(options)
    |> perform_action(options)
  end
  
  def parse_warnings(compilation_results, _) do
    Regex.scan(~r/warning:\s+(?<text>[^\n]+)\n\s*(?<filename>[^:]+)\:(?<line_number>\d+)(: (?<item>[^\n]+))?\n+/, compilation_results)
    |> Enum.map(
         fn([line, text, file_name, line_number, _,item]) -> %{line: line, warning_type: nil, text: text, file_name: file_name, line_number: String.to_integer(line_number), item: item}
           ([line, text, file_name, line_number]) -> %{line: line, warning_type: nil, text: text, file_name: file_name, line_number: String.to_integer(line_number), item: nil}
           (_) -> nil
         end
       )
    |> Enum.filter(&(&1))
    |> Enum.map(fn(v) -> %{v| warning_type: warning_type(v)} end)
  end
  
  
  def compilation_results(%{passive: true}) do
    {compile_output, 0} = System.cmd("mix", ["compile", "--all-warnings"], stderr_to_stdout: true)
    {:ok, compile_output}
  end
  def compilation_results(_) do
    {_clean_output, 0} = System.cmd("mix", ["clean"], stderr_to_stdout: true)
    {compile_output, 0} = System.cmd("mix", ["compile", "--force", "--all-warnings"], stderr_to_stdout: true)
    {:ok, compile_output}
  end
  

  def apply_filters(files, options) do
    files
    |> apply_line_filters(options)
    |> apply_file_filters(options)
  end
  
  def apply_line_filters(files, %{only: nil}), do: files
  def apply_line_filters(files, %{only: white_list}) do
    Enum.map(files, fn({file, lines}) ->
      lines = Enum.filter(lines, &(Enum.member?(white_list, &1.warning_type)))
      length(lines) > 0 && {file, lines} || nil
    end)
    |> Enum.filter(&(&1))
    |> Map.new()
  end

  def apply_file_filters(files, options) do
    cond do
      filters = options[:filters] ->
        Enum.filter(files, fn({file, _}) ->
          Enum.reduce_while(filters, true, fn(filter, acc) ->
            case filter do
              {:exclude, :all} -> {:halt, false}
              {:include, fs} -> Enum.member?(fs, file) && {:halt, true} || {:cont, acc}
              {:exclude, fs} -> Enum.member?(fs, file) && {:halt, false} || {:cont, acc}
            end
          end)
        end)
      :else -> files
    end
  end



  def warning_type(line) do
    cond do
      Regex.match?(~r/variable "(?<variable>[^\"]+)" is unused/, line.text) -> :vars
      Regex.match?(~r/module attribute @(?<variable>[^\s]+) was set but never used/, line.text) -> :attributes
      Regex.match?(~r/unused import (?<atom>.+)/, line.text) -> :imports
      Regex.match?(~r/unused alias (?<atom>.+)/, line.text) -> :aliases
      :else -> :other
    end
  end
  
  
  def output_header(options) do
    """
    ReRun Script
    =======================
    - generated_on: #{options.request_time}
    - options: #{options.request}
    
    """
  end

  def perform_action(files, options) do
    files = Enum.map(files, fn({file, v}) ->  fix({file, v}, options)  end)
    cond do
      output_file = options.output_file ->
        cl = Enum.map(files, fn({file, warnings_by_line}) ->
          file_header = ("""
                         # #{file}
                         #----------------------------------------------------
                         """)
          file_changes = Enum.map(warnings_by_line, fn({line, v}) ->
            line_header = "# #{file}:#{line} --> #{inspect v.patch, [pretty: false, line_limit: :infinity]}\n"
            lines = Enum.map(v.warnings,
                      fn(warning) ->
                        ("""
                         # #{warning.warning_type} -> #{inspect(warning.alteration, [pretty: false, line_limit: :infinity])}
                         #{warning.line}
                         """)
                      end) |> Enum.join("\n")
            line_header <> lines
          end) |> Enum.join("")
          file_header <> file_changes
        end) |> Enum.join("")
        File.write(output_file, output_header(options) <> cl  <> "\n")
      :else ->
        :ok
    end
  end
  
  
  def output_dry_run(file_name, line_no, line, :del, _) do
    IO.puts ("""
             #{file_name}:#{line_no}
             - #{line}
             """)
  end
  def output_dry_run(file_name, line_no, line, patched_line, _) do
    IO.puts ("""
             #{file_name}:#{line_no}
             > #{line}
             < #{patched_line}
             """)
  end


  def fix({file_name, warnings}, options) do
    with {:ok, file} <- File.read(file_name) do
      lines = file |> String.split("\n")
    
      by_line = Enum.group_by(warnings, &(&1.line_number))
      patches = Enum.map(by_line, fn({line_no, line_warnings}) ->
        line = Enum.at(lines, line_no - 1)
        {line_warnings, patch} = (Enum.map_reduce(line_warnings, line,
                                    fn(warning,replacement) ->
                                      r = @warning_type_regex[warning.warning_type]
                                      captures = r && Regex.named_captures(r, warning.text)
                                      patched = case captures && warning.warning_type do
                                                  :vars -> fix_unused_variable(captures["variable"], replacement, options)
                                                  :imports -> fix_unused_import(captures["atom"], "import", replacement, options)
                                                  :aliases -> fix_unused_alias(captures["atom"], "alias", replacement, options)
                                                  :attributes -> fix_unused_attribute(captures["atom"], replacement, options)
                                                  _ -> replacement
                                                end
                                      {Map.put(warning, :alteration, String.myers_difference(replacement, patched)), patched}
                                    end))
        patch = if (String.trim(patch) == ""), do: :del, else: patch
        options.dry_run && output_dry_run(file_name, line_no, line, patch, options)
        {
          line_no,
          patch,
          %{patch: String.myers_difference(line, patch != :del && patch || ""), warnings: line_warnings}
        }
      end)
      replacements = patches |> Enum.map(&({elem(&1, 0),elem(&1, 1)})) |> Map.new()
      by_line = patches |> Enum.map(&({elem(&1, 0),elem(&1, 2)})) |> Map.new()
      (!options[:dry_run] && !options[:output_file]) && patch_file(file_name, lines, replacements, options)
      {file_name, by_line}
  
    else
      e = {:error, _} ->
        if options.halt_on_error do
          raise "File Open Error #{inspect e}"
        end
        IO.puts "File Open Error #{inspect e}"
        {file_name, []}
      e  ->
        if options.halt_on_error do
          raise "File Open Error #{inspect e}"
        end
        IO.puts "File Open Error #{inspect e}"
        {file_name, []}
    end
  end
  
  def patch_file(file_name, lines, patches, _) do
    content = Enum.map_reduce(lines, 1,
                fn(line,line_no) ->
                  patch = cond do
                         patches[line_no] == :del -> nil
                         patches[line_no] -> patches[line_no]
                         :else -> line
                       end
                  {patch, line_no+1}
                end)
              |> elem(0)
              |> Enum.filter(&(&1))
              |> Enum.join("\n")
    File.write!(file_name, content)
  end
  
  
  def fix_unused_variable(variable, line, options) do
    cond do
      (line != (replacement = Regex.replace(~r/(^|[^\w])#{variable}([^\w]+)#{variable}([^\w]|$)/, line, "\\1#{variable}\\2_#{variable}\\3"))) -> replacement # %{symbol: symbol} -> %{symbol: _symbol}
      (line != (replacement = Regex.replace(~r/(^|[^\w])#{variable}([^\w]|$)/, line, "\\1_#{variable}\\2"))) -> replacement
      :else ->
        if options.halt_on_error do
          raise "Couldn't replace variable \"#{variable}\" in text [#{line}]"
        end
        IO.puts "Couldn't replace variable \"#{variable}\" in text [#{line}]"
        line
    end
  end
  
  def fix_unused_import(atom, keyword, line, options) do
    fix_unused_atom(atom, keyword, line, options)
  end
  
  def fix_unused_alias(atom, keyword, line, options) do
    fix_unused_atom(atom, keyword, line, options)
  end

  def fix_unused_attribute(atom, line, _options) do
    IO.puts "(\s*)\@(#{Regex.escape(atom)})(\s*)"
    if line != (replacement = Regex.replace(~r/(\s*)\@(#{Regex.escape(atom)})(\s*)/, line, "\\1@_\\2\\3")) do
      replacement
    else
      line
    end
  end
  
  def fix_unused_atom(atom, keyword, line, options) do
    line = cond do
             !is_nil(captures = Regex.named_captures(~r/(?:\w+\.)+(?<function>\w+)\/(?<arity>\d+)/, atom)) ->
               fix_unused_function(captures["function"], captures["arity"], atom, keyword, line, options)
             true -> fix_unused_module(atom, keyword, line, options)
           end
    # "import CoinHunter.Simulator, only: [simulate: 4]" ---> ", only: [simulate: 4]" ---> "" (`simulate` function is unused, but Elixir reports the whole import CoinHunter.Simulator as unused, because `simulate` is the only function imported from that module. In this case, we need to clean up the remaining ", only: [simulate: 4]")
    Regex.replace(~r/^,.*/, line, "")
  end
  
  def fix_unused_function(function, arity, atom, keyword, line, options) do
    cond do
      (line != (replacement = Regex.replace(~r/\[\s*#{Regex.escape(function)}:\s*#{Regex.escape(arity)}\s*,\s*/, line, "["))) -> replacement
      (line != (replacement = Regex.replace(~r/\s*,\s*#{Regex.escape(function)}:\s*#{Regex.escape(arity)}\s*\]/, line, "]"))) -> replacement
      (line != (replacement = Regex.replace(~r/,\s*#{Regex.escape(function)}:\s*#{Regex.escape(arity)}/, line, ""))) -> replacement
      :else ->
        if options.halt_on_error do
          raise "Couldn't replace #{keyword} \"#{atom}\" in text [#{line}] | #{inspect function} #{inspect arity}"
        end
        IO.puts "Couldn't replace #{keyword} \"#{atom}\" in text [#{line}] | #{inspect function} #{inspect arity}"
        line
    end
  end


  def fix_unused_module(atom, keyword = "alias", line, options) do
    cond do
      (line != (replacement = Regex.replace(~r/\s*#{keyword}\s+(?:\w+\.*)*,\s*as:\s*#{atom}(?:\s|$)/, line, ""))) -> replacement
      (line != (replacement = Regex.replace(~r/\s*#{Regex.escape(keyword)}\s+(?:\w+\.)*#{Regex.escape(atom)}\s*/, line, ""))) -> replacement
      (line != (replacement = Regex.replace(~r/{\s*#{Regex.escape(atom)}\s*,\s*/, line, "{"))) -> replacement
      (line != (replacement = Regex.replace(~r/\s*,\s*#{Regex.escape(atom)}\s*}/, line, "}"))) -> replacement
      (line != (replacement = Regex.replace(~r/,\s*#{Regex.escape(atom)}/, line, ""))) -> replacement
      (line != (replacement = Regex.replace(~r/\s*#{Regex.escape(keyword)}\s+[^{]+{\s*#{Regex.escape(atom)}\s*}\s*/, line, ""))) -> replacement
      :else ->
        if options.halt_on_error do
          raise "Couldn't replace #{inspect keyword} \"#{atom}\" in text [#{line}]"
        end
        IO.puts "Couldn't replace #{inspect keyword} \"#{atom}\" in text [#{line}]"
        line
    end
  end
  
  def fix_unused_module(atom, keyword, line, options) do
    cond do
      (line != (replacement = Regex.replace(~r/\s*#{Regex.escape(keyword)}\s+(?:\w+\.)*#{Regex.escape(atom)}\s*/, line, ""))) -> replacement
      (line != (replacement = Regex.replace(~r/{\s*#{Regex.escape(atom)}\s*,\s*/, line, "{"))) -> replacement
      (line != (replacement = Regex.replace(~r/\s*,\s*#{Regex.escape(atom)}\s*}/, line, "}"))) -> replacement
      (line != (replacement = Regex.replace(~r/,\s*#{Regex.escape(atom)}/, line, ""))) -> replacement
      (line != (replacement = Regex.replace(~r/\s*#{Regex.escape(keyword)}\s+[^{]+{\s*#{Regex.escape(atom)}\s*}\s*/, line, ""))) -> replacement
      :else ->
        if options.halt_on_error do
          raise "Couldn't replace #{inspect keyword} \"#{atom}\" in text [#{line}]"
        end
        IO.puts "Couldn't replace #{inspect keyword} \"#{atom}\" in text [#{line}]"
        line
    end
  end
  
  def get_line(filename, line) do
    File.read!(filename)
    |> String.split("\n")
    |> Enum.at(line - 1)
  end

end
