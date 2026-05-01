function notrail --description "Remove trailing spaces from a file"
    if test (count $argv) -eq 0
        echo "Usage: notrail <filename>" >&2
        return 1
    end

    if test (count $argv) -gt 1
        echo "🚫 Expected exactly one filename." >&2
        echo "Usage: notrail <filename>" >&2
        return 1
    end

    set -l filename $argv[1]

    if not test -f $filename
        echo "🚫 File not found: $filename" >&2
        return 1
    end

    python3 -S -c '
import sys
from pathlib import Path

path = Path(sys.argv[1])
lines = path.read_text().splitlines(keepends=True)

def remove_trailing_spaces(line):
    if line.endswith("\r\n"):
        return line[:-2].rstrip(" ") + "\r\n"
    if line.endswith("\n") or line.endswith("\r"):
        return line[:-1].rstrip(" ") + line[-1]
    return line.rstrip(" ")

path.write_text("".join(remove_trailing_spaces(line) for line in lines))
' $filename
    or begin
        echo "🚫 Failed to remove trailing spaces from: $filename" >&2
        return 1
    end
end
