# frozen_string_literal: true

# A stand-in for the draw.io desktop CLI, so tests do not depend on tools installed on the machine:
# it writes a fixed PNG to the --output path.
module FakeDrawioCli
  def with_fake_drawio_cli
    dir = Dir.mktmpdir
    script = File.join(dir, "fake-drawio")
    File.write(script, "#!/bin/sh\nwhile [ $# -gt 0 ]; do [ \"$1\" = \"--output\" ] && out=\"$2\"; shift; done\nprintf 'PNGDATA' > \"$out\"\n")
    File.chmod(0o755, script)
    ENV["ARCHSIGHT_DRAWIO_CLI"] = script
    yield
  ensure
    ENV.delete("ARCHSIGHT_DRAWIO_CLI")
    FileUtils.rm_rf(dir) if dir
  end
end
