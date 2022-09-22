defmodule ExFixer do
  def execute(options) do
    execute_for(warning_set(options), options)
  end
  
  def warning_set(options) do
    cond do
      options[:from_file] -> File.read!(options[:from_file])
      :else -> compilation_results()
    end
  end
  
  def compilation_results() do
    {_clean_output, 0} = System.cmd("mix", ["clean"], stderr_to_stdout: true)
    {compile_output, 0} = System.cmd("mix", ["compile", "--force"], stderr_to_stdout: true)
    compile_output
  end
  
  def execute_for(compilation_results, options \\ []) do
    compilation_results
    |> warnings()
    |> Enum.group_by(&(&1["filename"]))
    |> apply_filters(options)
    |> perform_action(options)
  end
  
  def warnings(compilation_results) do
    Regex.scan(~r/warning:\s+(?<text>[^\n]+)\n\s+(?<filename>[^:]+)\:(?<line_number>\d+)(: (?<item>[^\n]+))?\n+/, compilation_results)
    |> Enum.map(fn(entry) ->
      case entry do
        [line, text, filename, line_number, _,item] ->
          %{"line" => line, "fix_type" => fix_type(text), "text" => text, "filename" => filename, "line_number" => line_number, "item" => item}
        [line, text, filename, line_number] ->
          %{"line" => line, "fix_type" => fix_type(text), "text" => text, "filename" => filename, "line_number" => line_number, "item" => nil}
        _ -> nil
      end
    end)
    |> Enum.filter(&(&1))
  end
  
  def fix_type(text) do
    cond do
      !is_nil(Regex.named_captures(~r/variable "(?<variable>[^\"]+)" is unused/, text)) -> "var"
      !is_nil(Regex.named_captures(~r/unused import (?<atom>.+)/, text)) -> "import"
      !is_nil(Regex.named_captures(~r/unused alias (?<atom>.+)/, text)) -> "alias"
      true -> :other
    end
  end
  
  def apply_filters(files, options) do
    files
    |> apply_line_filters(options)
    |> apply_file_filters(options)
  end
  
  def apply_line_filters(files, options) do
    cond do
      only = options[:only] ->
        Enum.map(files, fn({file, lines}) ->
          lines = Enum.filter(lines, &(Enum.member?(only, &1["fix_type"])))
          length(lines) > 0 && {file, lines} || nil
        end)
        |> Enum.filter(&(&1))
        |> Map.new()
      :else -> files
    end
  end
  
  def apply_file_filters(files, options) do
    cond do
      filters = options[:filters] ->
        Enum.filter(files, fn({file, _}) ->
          Enum.reduce_while(filters, true, fn(filter, acc) ->
            case filter do
              {:exclude, :all} -> {:halt, false}
              {:include, fs} ->
                cond do
                  Enum.member?(fs, file) -> {:halt, true}
                  :else -> {:cont, acc}
                end
              {:exclude, fs} ->
                cond do
                  Enum.member?(fs, file) -> {:halt, false}
                  :else -> {:cont, acc}
                end
            end
          end)
        
        end)
      :else -> files
    end
  end
  
  
  def output_header(options) do
    """
    ReRun Script
    =======================
    - generated_on: #{options[:request_time]}
    - options: #{options[:request]}
    
    """
  end
  
  def perform_action(files, options) do
    files = Enum.map(files, fn({file, v}) ->  fix({file, v}, options)  end)
    
    cond do
      output_file = options[:output_file] ->
        change_log = Enum.map(files, fn({file, warnings_by_line}) ->
          file_header = """
          # #{file}
          #----------------------------------------------------
          """
          file_changes = Enum.map(warnings_by_line, fn({line, v}) ->
            line_header = "# #{file}:#{line} --> #{inspect v[:patch], [pretty: false, line_limit: :infinity]}\n"
            lines = Enum.map(v[:warnings], fn(warning) ->
              """
              # #{warning["fix_type"]} -> #{inspect(warning["alteration"], [pretty: false, line_limit: :infinity])}
              #{warning["line"]}
              """
            end) |> Enum.join("\n")
            line_header <> lines
          end) |> Enum.join("")
          file_header <> file_changes
        end) |> Enum.join("")
        File.write(output_file, output_header(options) <> change_log  <> "\n")
        IO.puts "Replay filter written to [#{output_file}]"
      :else ->
        :fin
    end
  end
  
  def fix({filename, warnings}, options) do
    lines = File.read!(filename) |> String.split("\n")
    by_line = Enum.group_by(warnings, &(&1["line_number"]))
    patches = Enum.map(by_line, fn({line_no, line_warnings}) ->
      line_no = String.to_integer(line_no)
      line = Enum.at(lines, line_no - 1)
      {line_warnings, patch} = Enum.map_reduce(line_warnings, line, fn(warning,replacement) ->
        u = case warning["fix_type"] do
              "var" ->
                cond do
                  captures = Regex.named_captures(~r/variable "(?<variable>[^\"]+)" is unused/, warning["text"]) ->
                    fix_unused_variable(captures["variable"], replacement)
                  :else -> replacement
                end
              "import" ->
                cond do
                  captures = Regex.named_captures(~r/unused import (?<atom>.+)/, warning["text"]) ->
                    fix_unused_import(captures["atom"], "import", replacement)
                  :else -> replacement
                end
              "alias" ->
                cond do
                  captures = Regex.named_captures(~r/unused alias (?<atom>.+)/, warning["text"])->
                    fix_unused_alias(captures["atom"], "alias", replacement)
                  :else -> replacement
                end
              _ -> replacement
            end
        {Map.put(warning, "alteration", String.myers_difference(replacement, u)), u}
      end)
      {l,u,p} = cond do
                  String.trim(patch) == "" -> {line_no, :delete, "[DEL LINE]"}
                  :else -> {line_no, patch, String.myers_difference(line, patch)}
                end
      
      cond do
        !options[:dry_run] -> :nop
        u == :delete ->
          IO.puts """
          #{filename}:#{line_no}
          - #{line}
          """
        :else ->
          IO.puts """
          #{filename}:#{line_no}
          > #{line}
          < #{u}
          """
      end
      {{l,u}, {line_no, %{patch: p, warnings: line_warnings}}}
    end)
    
    by_line = patches
              |> Enum.map(&(elem(&1, 1)))
              |> Map.new()
    
    lp = patches
         |> Enum.map(&(elem(&1, 0)))
         |> Map.new()


    if !options[:dry_run] && !options[:output_file] do
      content = Enum.map_reduce(lines, 1,
                  fn(l,ln) ->
                    lu = cond do
                           lp[ln] == :delete -> nil
                           lp[ln] -> lp[ln]
                           :else -> l
                         end
                    {lu, ln+1}
                  end)
                |> elem(0)
                |> Enum.filter(&(&1))
                |> Enum.join("\n")
  
      File.write!(filename, content)
    end
    {filename, by_line}
  end
  
  def fix_unused_variable(variable, line) do
    cond do
      (line != (replacement = Regex.replace(~r/(^|[^\w])#{variable}([^\w]+)#{variable}([^\w]|$)/, line, "\\1#{variable}\\2_#{variable}\\3"))) -> replacement # %{symbol: symbol} -> %{symbol: _symbol}
      (line != (replacement = Regex.replace(~r/(^|[^\w])#{variable}([^\w]|$)/, line, "\\1_#{variable}\\2"))) -> replacement
      :else ->
        IO.puts "Couldn't replace variable \"#{variable}\" in text [#{line}]"
        line
    end
  end
  
  def fix_unused_import(atom, keyword, line) do
    fix_unused_atom(atom, keyword, line)
  end
  
  def fix_unused_alias(atom, keyword, line) do
    fix_unused_atom(atom, keyword, line)
  end
  
  def fix_unused_atom(atom, keyword, line) do
    line = cond do
             !is_nil(captures = Regex.named_captures(~r/(?:\w+\.)+(?<function>\w+)\/(?<arity>\d+)/, atom)) ->
               fix_unused_function(captures["function"], captures["arity"], atom, keyword, line)
             true -> fix_unused_module(atom, keyword, line)
           end
    # "import CoinHunter.Simulator, only: [simulate: 4]" ---> ", only: [simulate: 4]" ---> "" (`simulate` function is unused, but Elixir reports the whole import CoinHunter.Simulator as unused, because `simulate` is the only function imported from that module. In this case, we need to clean up the remaining ", only: [simulate: 4]")
    Regex.replace(~r/^,.*/, line, "")
  end
  
  def fix_unused_function(function, arity, atom, keyword, line) do
    cond do
      (line != (replacement = Regex.replace(~r/\[\s*#{Regex.escape(function)}:\s*#{Regex.escape(arity)}\s*,\s*/, line, "["))) -> replacement
      (line != (replacement = Regex.replace(~r/\s*,\s*#{Regex.escape(function)}:\s*#{Regex.escape(arity)}\s*\]/, line, "]"))) -> replacement
      (line != (replacement = Regex.replace(~r/,\s*#{Regex.escape(function)}:\s*#{Regex.escape(arity)}/, line, ""))) -> replacement
      :else ->
        IO.puts "Couldn't replace #{keyword} \"#{atom}\" in text [#{line}] | #{inspect function} #{inspect arity}"
        line
    end
  end


  def fix_unused_module(atom, keyword = "alias", line) do
    cond do
      (line != (replacement = Regex.replace(~r/\s*#{keyword}\s+(?:\w+\.*)*,\s*as:\s*#{atom}(?:\s|$)/, line, ""))) -> replacement
      (line != (replacement = Regex.replace(~r/\s*#{Regex.escape(keyword)}\s+(?:\w+\.)*#{Regex.escape(atom)}\s*/, line, ""))) -> replacement
      (line != (replacement = Regex.replace(~r/{\s*#{Regex.escape(atom)}\s*,\s*/, line, "{"))) -> replacement
      (line != (replacement = Regex.replace(~r/\s*,\s*#{Regex.escape(atom)}\s*}/, line, "}"))) -> replacement
      (line != (replacement = Regex.replace(~r/,\s*#{Regex.escape(atom)}/, line, ""))) -> replacement
      (line != (replacement = Regex.replace(~r/\s*#{Regex.escape(keyword)}\s+[^{]+{\s*#{Regex.escape(atom)}\s*}\s*/, line, ""))) -> replacement
      :else ->
        IO.puts "Couldn't replace #{inspect keyword} \"#{atom}\" in text [#{line}]"
        line
    end
  end
  
  def fix_unused_module(atom, keyword, line) do
    cond do
      (line != (replacement = Regex.replace(~r/\s*#{Regex.escape(keyword)}\s+(?:\w+\.)*#{Regex.escape(atom)}\s*/, line, ""))) -> replacement
      (line != (replacement = Regex.replace(~r/{\s*#{Regex.escape(atom)}\s*,\s*/, line, "{"))) -> replacement
      (line != (replacement = Regex.replace(~r/\s*,\s*#{Regex.escape(atom)}\s*}/, line, "}"))) -> replacement
      (line != (replacement = Regex.replace(~r/,\s*#{Regex.escape(atom)}/, line, ""))) -> replacement
      (line != (replacement = Regex.replace(~r/\s*#{Regex.escape(keyword)}\s+[^{]+{\s*#{Regex.escape(atom)}\s*}\s*/, line, ""))) -> replacement
      :else ->
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
