defmodule Mix.Tasks.FilterTest do
  use ExUnit.Case
  import ExUnit.CaptureIO

  test "prints matching lines without color by default" do
    path = write_file!("alpha beta\nbeta\n")

    output =
      capture_io(fn ->
        Mix.Task.reenable("filter")
        Mix.Tasks.Filter.run([path, "alpha"])
      end)

    assert output == "alpha beta\n"
  end

  test "colors matched text when color modifier is set as a flag" do
    path = write_file!("alpha beta\nbeta\n")

    output =
      capture_io(fn ->
        Mix.Task.reenable("filter")
        Mix.Tasks.Filter.run([path, "alpha", "--modifier", "color"])
      end)

    assert output =~ "\e[33malpha\e[0m"
  end

  test "supports named colors" do
    path = write_file!("alpha beta\n")

    output =
      capture_io(fn ->
        Mix.Task.reenable("filter")
        Mix.Tasks.Filter.run([path, "alpha", "--modifier", "color=red"])
      end)

    assert output =~ "\e[31malpha\e[0m"
  end

  test "raises for unsupported color values" do
    path = write_file!("alpha beta\n")

    assert_raise Mix.Error, "Unsupported color modifier: orange", fn ->
      capture_io(fn ->
        Mix.Task.reenable("filter")
        Mix.Tasks.Filter.run([path, "alpha", "--modifier", "color=orange"])
      end)
    end
  end

  test "searches directories recursively" do
    dir = make_dir!()
    nested = Path.join(dir, "nested")
    File.mkdir_p!(nested)
    file_a = Path.join(dir, "a.txt")
    file_b = Path.join(nested, "b.txt")
    File.write!(file_a, "alpha beta\n")
    File.write!(file_b, "gamma\nalpha delta\n")

    output =
      capture_io(fn ->
        Mix.Task.reenable("filter")
        Mix.Tasks.Filter.run([dir, "alpha"])
      end)

    assert output =~ "#{file_a}:alpha beta"
    assert output =~ "#{file_b}:alpha delta"
  end

  test "prints only match count when count modifier is present for a file" do
    path = write_file!("alpha beta\nalpha gamma\nbeta\n")

    output =
      capture_io(fn ->
        Mix.Task.reenable("filter")
        Mix.Tasks.Filter.run([path, "alpha", "--modifier", "count"])
      end)

    assert output == "2\n"
  end

  test "prints only match count when count modifier is present for a directory" do
    dir = make_dir!()
    nested = Path.join(dir, "nested")
    File.mkdir_p!(nested)
    file_a = Path.join(dir, "a.txt")
    file_b = Path.join(nested, "b.txt")
    File.write!(file_a, "alpha beta\n")
    File.write!(file_b, "alpha delta\nalpha zeta\n")

    output =
      capture_io(fn ->
        Mix.Task.reenable("filter")
        Mix.Tasks.Filter.run([dir, "alpha", "--modifier", "count"])
      end)

    assert output == "3\n"
  end

  test "supports regex queries in CLI" do
    path = write_file!("alpha one\nbeta one\nalpha two\n")

    output =
      capture_io(fn ->
        Mix.Task.reenable("filter")
        Mix.Tasks.Filter.run([path, "/[a-z]+ one/"])
      end)

    assert output =~ "alpha one"
    assert output =~ "beta one"
    refute output =~ "alpha two"
  end

  test "raises for invalid regex query" do
    path = write_file!("alpha\n")

    assert_raise Mix.Error, "Invalid regex query: /(unclosed/", fn ->
      capture_io(fn ->
        Mix.Task.reenable("filter")
        Mix.Tasks.Filter.run([path, "/(unclosed/"])
      end)
    end
  end

  test "shows surrounding lines when context modifier is set" do
    path = write_file!("zero\nalpha one\ntwo\nthree\n")

    output =
      capture_io(fn ->
        Mix.Task.reenable("filter")
        Mix.Tasks.Filter.run([path, "alpha", "--modifier", "context=1"])
      end)

    assert output =~ "[1] #{path}:2"
    assert output =~ "  1: zero"
    assert output =~ "> 2: alpha one"
    assert output =~ "  3: two"
  end

  test "supports context with directory searches" do
    dir = make_dir!()
    file_path = Path.join(dir, "a.txt")
    File.write!(file_path, "one\nalpha\ntwo\n")

    output =
      capture_io(fn ->
        Mix.Task.reenable("filter")
        Mix.Tasks.Filter.run([dir, "alpha", "--modifier", "context=1"])
      end)

    assert output =~ "[1] #{file_path}:2"
    assert output =~ "  1: one"
    assert output =~ "> 2: alpha"
    assert output =~ "  3: two"
  end

  test "raises for invalid context modifier values" do
    path = write_file!("alpha\n")

    assert_raise Mix.Error, "context modifier must be a non-negative integer: nope", fn ->
      capture_io(fn ->
        Mix.Task.reenable("filter")
        Mix.Tasks.Filter.run([path, "alpha", "--modifier", "context=nope"])
      end)
    end
  end

  test "standard flags combine case-insensitive matching, numbering and color" do
    path = write_file!("zero\nALPHA alpha\nlast\n")
    output = run_filter([path, "alpha", "--ignore-case", "--line-number", "--color"])
    assert output == "2:\e[33mALPHA\e[0m \e[33malpha\e[0m\n"
  end

  test "regex highlights preserve original casing with case-insensitive matching" do
    path = write_file!("Alpha 12\n")

    assert run_filter([path, "/alpha [0-9]+/", "-i", "--color-name", "red"]) ==
             "\e[31mAlpha 12\e[0m\n"
  end

  test "standard context and short aliases show numbered context with matching text highlighted" do
    path = write_file!("zero\nALPHA\ntwo\n")
    output = run_filter([path, "alpha", "-i", "-n", "-C", "1", "--color"])
    assert output =~ "[1] #{path}:2"
    assert output =~ "  1: zero"
    assert output =~ "> 2: \e[33mALPHA\e[0m"
    assert output =~ "  3: two"
  end

  test "count takes precedence over context, color and line numbers" do
    path = write_file!("Alpha alpha\nALPHA\n")
    assert run_filter([path, "alpha", "-i", "-c", "-n", "--context", "1", "--color"]) == "2\n"
  end

  test "directory results use path:line:text and support repeated include and exclude flags" do
    dir = make_dir!()
    File.mkdir_p!(Path.join(dir, "_build"))

    for file <- ["a.ex", "b.exs", "c.txt", "_build/d.ex"] do
      File.write!(Path.join(dir, file), "zero\nALPHA\n")
    end

    assert run_filter([
             dir,
             "alpha",
             "-i",
             "-n",
             "--include",
             "*.ex",
             "--include",
             "*.exs",
             "--exclude",
             "_build",
             "--exclude",
             "a.ex"
           ]) == "#{dir}/b.exs:2:ALPHA\n"
  end

  test "standard flags and legacy modifiers respect command-line order" do
    path = write_file!("ALPHA\nalpha\n")

    assert run_filter([path, "alpha", "--modifier", "ignore-case", "--no-ignore-case"]) ==
             "alpha\n"

    assert run_filter([path, "alpha", "--no-ignore-case", "--modifier", "ignore-case", "--count"]) ==
             "2\n"

    assert run_filter([path, "alpha", "--modifier", "count", "--no-count"]) == "alpha\n"
    assert run_filter([path, "alpha", "--color-name", "red", "--no-color"]) == "alpha\n"

    assert run_filter([path, "alpha", "--modifier", "color=red", "--color"]) ==
             "\e[33malpha\e[0m\n"

    assert run_filter([path, "alpha", "--line-number", "--no-line-number"]) == "alpha\n"
  end

  test "last context value wins across standard flags and modifiers" do
    path = write_file!("zero\nalpha\ntwo\n")
    assert run_filter([path, "alpha", "--context", "1", "--modifier", "context=0"]) == "alpha\n"
    assert run_filter([path, "alpha", "--modifier", "context=0", "--context", "1"]) =~ "  1: zero"
  end

  test "legacy modifiers support the new search options" do
    path = write_file!("ALPHA\n")

    assert run_filter([
             path,
             "alpha",
             "--modifier",
             "ignore-case",
             "--modifier",
             "line-number",
             "--modifier",
             "include=*.txt"
           ]) == "1:ALPHA\n"
  end

  test "invalid flags, missing values, extra arguments and invalid context raise useful errors" do
    path = write_file!("alpha")

    for args <- [["--unknown"], ["--context"], ["--context", "bad"], ["--include"], ["extra"]] do
      assert_raise Mix.Error, fn -> run_filter([path, "alpha"] ++ args) end
    end

    assert_raise Mix.Error, "context modifier must be a non-negative integer: -1", fn ->
      run_filter([path, "alpha", "--count", "--context", "-1"])
    end

    assert_raise Mix.Error, "Unsupported color modifier: orange", fn ->
      run_filter([path, "missing", "--color-name", "orange"])
    end

    assert_raise Mix.Error, "include requires a non-empty glob pattern", fn ->
      run_filter([path, "alpha", "--include", ""])
    end
  end

  defp run_filter(args) do
    capture_io(fn -> Mix.Tasks.Filter.run(args) end)
  end

  defp write_file!(contents) do
    path =
      Path.join(
        System.tmp_dir!(),
        "searchie-#{System.system_time(:nanosecond)}-#{System.unique_integer([:positive])}.txt"
      )

    File.write!(path, contents)
    on_exit(fn -> File.rm!(path) end)
    path
  end

  defp make_dir! do
    path =
      Path.join(
        System.tmp_dir!(),
        "searchie-dir-#{System.system_time(:nanosecond)}-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(path)
    on_exit(fn -> File.rm_rf!(path) end)
    path
  end
end
