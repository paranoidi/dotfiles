function notabs --description "Replace tabs with 4 spaces in a file"
    if test (count $argv) -eq 0
        echo "Usage: notabs <filename>" >&2
        return 1
    end

    if test (count $argv) -gt 1
        echo "🚫 Expected exactly one filename." >&2
        echo "Usage: notabs <filename>" >&2
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
path.write_text(path.read_text().replace("\t", "    "))
' $filename
    or begin
        echo "🚫 Failed to replace tabs in: $filename" >&2
        return 1
    end
end
