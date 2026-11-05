defmodule Searchie.EscriptTest do
  use ExUnit.Case
  import ExUnit.CaptureIO

  setup_all do
    capture_io(fn -> Mix.Task.run("escript.build") end)
    dir = Path.join(System.tmp_dir!(), "searchie-escript-#{System.system_time(:nanosecond)}")
    File.mkdir_p!(dir)
    script = Path.join(dir, "searchie")
    File.cp!("searchie", script)
    File.chmod!(script, 0o755)
    File.write!(Path.join(dir, "input.txt"), "before\nERROR 12\nafter\n")
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir, script: script}
  end

  test "packaged CLI runs outside the repository with matching output and status 0", ctx do
    assert {"2:ERROR 12\n", 0} = run(ctx, ["input.txt", "error", "-i", "-n"])
    {output, 0} = run(ctx, ["input.txt", "/error [0-9]+/", "-i", "-C", "1"])
    assert output =~ "  1: before"
    assert output =~ "> 2: ERROR 12"
    assert output =~ "  3: after"
  end

  test "no matches return status 1, including count output", ctx do
    assert {"", 1} = run(ctx, ["input.txt", "absent"])
    assert {"0\n", 1} = run(ctx, ["input.txt", "absent", "--count"])
  end

  test "missing files, invalid options and invalid regex return status 2", ctx do
    for args <- [["missing.txt", "error"], ["input.txt", "/[/"], ["--bad-option"], []] do
      {output, 2} = run(ctx, args)
      refute output == ""
      refute output =~ "** ("
    end

    {output, 0} = run(ctx, ["--help"])
    assert output =~ "Usage: searchie"
  end

  test "recursive partial failures retain matches and return status 2", ctx do
    data = Path.join(ctx.dir, "data")
    File.mkdir_p!(data)
    File.write!(Path.join(data, "good.txt"), "error\n")
    File.ln_s!(Path.join(data, "missing"), Path.join(data, "broken.txt"))
    {output, 2} = run(ctx, ["data", "error", "--count"])
    assert output =~ "1\n"
    assert output =~ "data/broken.txt: no such file or directory"
  end

  defp run(ctx, args) do
    System.cmd(ctx.script, args,
      cd: ctx.dir,
      stderr_to_stdout: true,
      env: [{"ERL_FLAGS", "+S 2:2"}]
    )
  end
end
