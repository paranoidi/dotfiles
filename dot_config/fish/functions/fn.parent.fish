function fn.parent -d " Path [/etc/sudo.conf -> /etc]"
    python3 -S -c "
import sys
from pathlib import Path

fname = sys.stdin.read().strip()
p = Path(fname)
print(p.parent)
"
end

