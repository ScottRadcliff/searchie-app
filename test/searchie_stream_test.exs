defmodule SearchieStreamTest do
  use ExUnit.Case

  setup do
    dir = Path.join(System.tmp_dir!(), "searchie-stream-#{System.system_time(:nanosecond)}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir}
  end

  test "context is complete for adjacent hits and matches at both file boundaries", %{dir: dir} do
    lines = ["hit first", "hit adjacent", "", "middle", "hit near end", "hit last"]
    path = Path.join(dir, "context.txt")
    File.write!(path, Enum.join(lines, "\n"))

    for context <- [1, 2, 10] do
      assert {:ok, result} =
               Searchie.scan(path, "hit", [], [], fn match, acc -> [match | acc] end, context)

      matches = Enum.reverse(result.value)
      assert result.count == 4
      assert result.errors == []
      assert Enum.map(matches, & &1.line_number) == [1, 2, 5, 6]

      Enum.each(matches, fn match ->
        expected =
          lines
          |> Enum.with_index(1)
          |> Enum.filter(fn {_, n} ->
            abs(n - match.line_number) <= context
          end)
          |> Enum.map(fn {text, n} -> {n, text} end)

        assert match.context == expected
      end)
    end
  end

  test "physical lines handle empty files, blank lines and a trailing newline", %{dir: dir} do
    path = Path.join(dir, "lines.txt")

    for {content, numbers} <- [{"", []}, {"\n", [1]}, {"one\n", [1]}, {"one\n\nlast", [1, 2, 3]}] do
      File.write!(path, content)
      assert {:ok, %{matches: matches, errors: []}} = Searchie.filter(path, "")
      assert Enum.map(matches, & &1.line_number) == numbers
    end
  end

  test "large scans can count matches without accumulating file contents", %{dir: dir} do
    path = Path.join(dir, "large.txt")

    File.open!(path, [:write], fn io ->
      for _ <- 1..100 do
        IO.binwrite(io, String.duplicate("hit large-file line\n", 1_000))
      end
    end)

    assert {:ok, %{count: 100_000, value: 100_000, errors: []}} =
             Searchie.scan(path, "hit", [], 0, fn _match, count -> count + 1 end)
  end

  test "invalid text reports an error while preserving preceding matches and available context",
       %{dir: dir} do
    path = Path.join(dir, "bad.txt")
    File.write!(path, ["hit\nnext\n", <<255>>, "\n"])

    assert {:ok,
            %{count: 1, value: [match], errors: [%{file_path: ^path, reason: :invalid_encoding}]}} =
             Searchie.scan(path, "hit", [], [], fn match, acc -> [match | acc] end, 3)

    assert match.context == [{1, "hit"}, {2, "next"}]
  end

  test "directory failures preserve matches and traversal continues", %{dir: dir} do
    File.write!(Path.join(dir, "a.txt"), "hit\n")
    broken = Path.join(dir, "b-broken.txt")
    File.ln_s!(Path.join(dir, "missing-target"), broken)
    File.write!(Path.join(dir, "c.txt"), "hit\n")

    assert {:ok, %{matches: matches, errors: [%{file_path: ^broken, reason: :enoent}]}} =
             Searchie.filter(dir, "hit")

    assert Enum.map(matches, &Path.basename(&1.file_path)) == ["a.txt", "c.txt"]
  end

  test "directory symlink cycles are skipped and file symlinks are searchable", %{dir: dir} do
    original = Path.join(dir, "a.txt")
    File.write!(original, "hit\n")
    File.ln_s!(dir, Path.join(dir, "cycle"))
    File.ln_s!(original, Path.join(dir, "linked.txt"))
    assert {:ok, %{matches: matches, errors: []}} = Searchie.filter(dir, "hit")
    assert Enum.map(matches, &Path.basename(&1.file_path)) == ["a.txt", "linked.txt"]
  end

  test "excluded directories do not produce errors from their broken entries", %{dir: dir} do
    excluded = Path.join(dir, "generated")
    File.mkdir_p!(excluded)
    File.ln_s!(Path.join(dir, "missing"), Path.join(excluded, "broken.txt"))

    assert {:ok, %{matches: [], errors: []}} =
             Searchie.filter(dir, "hit", [{"exclude", "generated"}])
  end

  test "root filesystem errors and invalid filters are returned rather than raised", %{dir: dir} do
    path = Path.join(dir, "a.txt")
    File.write!(path, "hit")
    bad_path = Path.join(path, "child")
    assert {:error, {:file_error, ^bad_path, :enotdir}} = Searchie.filter(bad_path, "hit")

    assert {:error, {:invalid_pattern, "include"}} =
             Searchie.filter(path, "hit", [{"include", true}])

    assert {:error, {:invalid_glob, "{"}} = Searchie.filter(path, "hit", [{"include", "{"}])
  end
end
