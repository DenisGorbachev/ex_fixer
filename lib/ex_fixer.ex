defmodule ExFixer do
  def execute() do
    execute_for(compilation_results())
  end

  def compilation_results() do
    {_clean_output, 0} = System.cmd("mix", ["clean"], stderr_to_stdout: true)
    {compile_output, 0} = System.cmd("mix", ["compile", "--force"], stderr_to_stdout: true)
    compile_output
  end

  def execute_for(compilation_results) do
    compilation_results |> warnings() |> Enum.group_by(&(&1["filename"])) |> Enum.map(&(fix(elem(&1, 0), elem(&1, 1))))
  end

  def warnings(compilation_results) do
    Regex.scan(~r/warning:\s+(?<text>[^\n]+)\n\s*(?<filename>[^:]+)\:(?<line_number>\d+)\n/, compilation_results)
    |> Enum.map(&(%{"text" => Enum.at(&1, 1), "filename" => Enum.at(&1, 2), "line_number" => Enum.at(&1, 3)}))
  end

  def fix(filename, warnings) do
    lines = File.read!(filename) |> String.split("\n")
    lines = warnings |> Enum.reduce(lines, &(fix_warning(&1, &2)))
    content = lines |> Enum.filter(&(!is_nil(&1))) |> Enum.join("\n")
    File.write!(filename, content)
  end

  def fix_warning(warning, lines) do
    _filename = warning["_filename"]
    {line_number, ""} = Integer.parse(warning["line_number"])
    lines |> List.update_at(line_number - 1, &(fix_warning_at(warning, &1)))
  end

  def fix_warning_at(warning, line) do
    replacement = cond do
      !is_nil(captures = Regex.named_captures(~r/variable "(?<variable>[^\"]+)" is unused/, warning["text"])) -> fix_unused_variable(captures["variable"], line)
      !is_nil(captures = Regex.named_captures(~r/unused import (?<atom>.+)/, warning["text"])) -> fix_unused_import(captures["atom"], "import", line)
      !is_nil(captures = Regex.named_captures(~r/unused alias (?<atom>.+)/, warning["text"])) -> fix_unused_alias(captures["atom"], "alias", line)
      true -> line # raise "Can't fix \"#{warning["text"]}\" in #{warning["filename"]}:#{warning["line"]}"
    end
    if replacement |> String.trim() |> String.length() > 0, do: replacement, else: nil
  end

  def fix_unused_variable(variable, line) do
    cond do
      (line != (replacement = Regex.replace(~r/(^|[^\w])#{variable}([^\w]+)#{variable}([^\w]|$)/, line, "\\1#{variable}\\2_#{variable}\\3"))) -> replacement # %{symbol: symbol} -> %{symbol: _symbol}
      (line != (replacement = Regex.replace(~r/(^|[^\w])#{variable}([^\w]|$)/, line, "\\1_#{variable}\\2"))) -> replacement
      true -> raise "Couldn't replace variable \"#{variable}\" in text \"#{line}\""
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
      !is_nil(captures = Regex.named_captures(~r/(?:\w+\.)+(?<function>\w+)\/(?<arity>\d+)/, atom)) -> fix_unused_function(captures["function"], captures["arity"], atom, keyword, line)
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
      true -> raise "Couldn't replace #{keyword} \"#{atom}\" in text \"#{line}\""
    end
  end

  def fix_unused_module(atom, keyword, line) do
    cond do
      (line != (replacement = Regex.replace(~r/\s*#{Regex.escape(keyword)}\s+(?:\w+\.)*#{Regex.escape(atom)}\s*/, line, ""))) -> replacement
      (line != (replacement = Regex.replace(~r/{\s*#{Regex.escape(atom)}\s*,\s*/, line, "{"))) -> replacement
      (line != (replacement = Regex.replace(~r/\s*,\s*#{Regex.escape(atom)}\s*}/, line, "}"))) -> replacement
      (line != (replacement = Regex.replace(~r/,\s*#{Regex.escape(atom)}/, line, ""))) -> replacement
      (line != (replacement = Regex.replace(~r/\s*#{Regex.escape(keyword)}\s+[^{]+{\s*#{Regex.escape(atom)}\s*}\s*/, line, ""))) -> replacement
      true -> raise "Couldn't replace #{keyword} \"#{atom}\" in text \"#{line}\""
    end
  end

  def get_line(filename, line) do
    File.read!(filename)
    |> String.split("\n")
    |> Enum.at(line - 1)
  end

end
