defmodule Searchie.CLITest do
  use ExUnit.Case
  import ExUnit.CaptureIO

  setup do
    dir = Path.join(System.tmp_dir!(), "searchie-cli-#{System.system_time(:nanosecond)}")
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "good.txt"), "hit\n")
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir}
  end

  test "console calls return statuses without halting the VM", %{dir: dir} do
    path = Path.join(dir, "good.txt")
    assert capture_io(fn -> assert {:ok, 0} = Searchie.CLI.run([path, "hit"]) end) == "hit\n"
    assert capture_io(fn -> assert {:ok, 1} = Searchie.CLI.run([path, "missing"]) end) == ""

    assert capture_io(fn -> assert {:ok, 1} = Searchie.CLI.run([path, "missing", "-c"]) end) ==
             "0\n"

    assert {:error, "Invalid regex query: /[/"} = Searchie.CLI.run([path, "/[/"])
  end

  test "partial failures go to stderr and successful output stays on stdout", %{dir: dir} do
    broken = Path.join(dir, "broken.txt")
    File.ln_s!(Path.join(dir, "missing"), broken)

    stderr =
      capture_io(:stderr, fn ->
        stdout = capture_io(fn -> assert {:ok, 2} = Searchie.CLI.run([dir, "hit", "-c"]) end)
        assert stdout == "1\n"
      end)

    assert stderr =~ broken
    assert stderr =~ "no such file or directory"
  end

  test "empty or invalid arguments return readable errors", %{dir: dir} do
    assert {:error, message} = Searchie.CLI.run([])
    assert message =~ "Usage: searchie"
    assert {:error, "Invalid glob pattern: {"} = Searchie.CLI.run([dir, "hit", "--include", "{"])
    assert capture_io(fn -> assert {:ok, 0} = Searchie.CLI.run(["--help"]) end) =~ "Exit codes:"
  end
end
