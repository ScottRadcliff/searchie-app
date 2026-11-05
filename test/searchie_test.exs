defmodule SearchieTest do
  use ExUnit.Case

  describe "filter/3" do
    test "returns lines containing the query" do
      path = write_file!("alpha\nbeta\nalphabet\ngamma\n")

      assert {:ok, %{matches: matches, modifiers: []}} = Searchie.filter(path, "alpha")
      assert Enum.map(matches, & &1.line_text) == ["alpha", "alphabet"]
      assert Enum.map(matches, & &1.line_number) == [1, 3]
      assert Enum.all?(matches, &(&1.file_path == path))
    end

    test "returns no matches when query is absent" do
      path = write_file!("alpha\nbeta\n")

      assert {:ok, %{matches: [], modifiers: []}} = Searchie.filter(path, "delta")
    end

    test "returns file-not-found for missing files" do
      assert {:error, :enoent} =
               Searchie.filter("/tmp/does-not-exist-#{System.unique_integer()}", "x")
    end

    test "preserves presentation modifiers in the result" do
      path = write_file!("red\nblue\n")
      modifiers = [{"count", true}, {"context", "2"}]

      assert {:ok, %{matches: matches, modifiers: ^modifiers}} =
               Searchie.filter(path, "red", modifiers)

      assert Enum.map(matches, & &1.line_text) == ["red"]
    end

    test "supports recursive directory search" do
      dir = make_dir!()
      file_a = Path.join(dir, "a.txt")
      nested = Path.join(dir, "nested")
      file_b = Path.join(nested, "b.txt")
      File.mkdir_p!(nested)
      File.write!(file_a, "alpha one\nbeta two\n")
      File.write!(file_b, "gamma three\nalpha four\n")

      assert {:ok, %{matches: matches, modifiers: []}} = Searchie.filter(dir, "alpha")
      assert Enum.any?(matches, &(&1.file_path == file_a and &1.line_text == "alpha one"))
      assert Enum.any?(matches, &(&1.file_path == file_b and &1.line_text == "alpha four"))
    end

    test "supports regex query when wrapped in slashes" do
      path = write_file!("alpha one\nbeta one\nalpha two\n")

      assert {:ok, %{matches: matches, modifiers: []}} = Searchie.filter(path, "/[a-z]+ one/")
      assert Enum.map(matches, & &1.line_text) == ["alpha one", "beta one"]
    end

    test "returns invalid regex error for malformed regex query" do
      path = write_file!("alpha\n")
      assert {:error, :invalid_regex} = Searchie.filter(path, "/(unclosed/")
    end
  end

  test "literal and regex queries support case-insensitive matching without changing text" do
    path = write_file!("Alpha
ALPHA
alpha
other
")

    for query <- ["alpha", "/^alpha$/"] do
      assert {:ok, %{matches: matches}} = Searchie.filter(path, query, [{"ignore-case", true}])
      assert Enum.map(matches, & &1.line_text) == ["Alpha", "ALPHA", "alpha"]
      assert Enum.map(matches, & &1.line_number) == [1, 2, 3]
    end

    assert {:ok, %{matches: matches}} = Searchie.filter(path, "alpha")
    assert Enum.map(matches, & &1.line_text) == ["alpha"]
  end

  test "case-insensitive literal matching escapes regex characters and supports Unicode" do
    path = write_file!("CAFÉ.txt
caféXtxt
")

    assert {:ok, %{matches: [match]}} =
             Searchie.filter(path, "café.txt", [{"ignore-case", true}])

    assert match.line_text == "CAFÉ.txt"
  end

  test "last boolean modifier wins" do
    path = write_file!("ALPHA
alpha
")

    for disabled <- [false, "false"] do
      assert {:ok, %{matches: [match]}} =
               Searchie.filter(path, "alpha", [
                 {"ignore-case", true},
                 {"ignore-case", disabled}
               ])

      assert match.line_text == "alpha"
    end
  end

  test "file patterns combine includes as a union and exclusions take priority" do
    dir = make_dir!()

    for file <- [
          "a.ex",
          "b.exs",
          "c.txt",
          "nested/d.ex",
          "nested/skip.ex",
          "_build/generated.ex",
          "nested/_build/generated.ex",
          ".git/config"
        ] do
      path = Path.join(dir, file)
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, "alpha\n")
    end

    modifiers = [
      {"include", "*.ex"},
      {"include", "*.exs"},
      {"exclude", "_build"},
      {"exclude", "skip.*"},
      {"exclude", ".git"}
    ]

    assert {:ok, %{matches: matches, modifiers: ^modifiers}} =
             Searchie.filter(dir, "alpha", modifiers)

    assert Enum.map(matches, &Path.relative_to(&1.file_path, dir)) == [
             "a.ex",
             "b.exs",
             "nested/d.ex"
           ]
  end

  test "patterns containing slashes are relative to the search root" do
    dir = make_dir!()

    for file <- ["lib/a.ex", "lib/deep/b.ex", "other/lib/c.ex"] do
      path = Path.join(dir, file)
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, "alpha")
    end

    assert {:ok, %{matches: matches}} = Searchie.filter(dir, "alpha", [{"include", "lib/*.ex"}])
    assert Enum.map(matches, &Path.relative_to(&1.file_path, dir)) == ["lib/a.ex"]

    assert {:ok, %{matches: matches}} =
             Searchie.filter(dir, "alpha", [
               {"include", "lib/**/*.ex"},
               {"exclude", "lib/deep/"}
             ])

    assert Enum.map(matches, &Path.relative_to(&1.file_path, dir)) == ["lib/a.ex"]
  end

  test "hidden files can be searched and excluded explicitly" do
    dir = make_dir!()
    File.mkdir_p!(Path.join(dir, ".git"))
    File.write!(Path.join(dir, ".git/config"), "alpha")
    File.write!(Path.join(dir, ".hidden"), "alpha")
    assert {:ok, %{matches: matches}} = Searchie.filter(dir, "alpha", [{"exclude", ".git"}])
    assert Enum.map(matches, &Path.basename(&1.file_path)) == [".hidden"]
  end

  test "patterns also apply to individual files and unmatched includes yield no results" do
    path = write_file!("alpha")
    assert {:ok, %{matches: []}} = Searchie.filter(path, "alpha", [{"include", "*.ex"}])
    assert {:ok, %{matches: []}} = Searchie.filter(path, "alpha", [{"exclude", "*.txt"}])
    assert {:ok, %{matches: [_]}} = Searchie.filter(path, "alpha", [{"include", "*.txt"}])
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
