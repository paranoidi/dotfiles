function fn.name -d " Path [/etc/sudo.conf -> sudo.conf]"
    python3 -S -c "
import sys
from pathlib import Path

fname = sys.stdin.read().strip()
p = Path(fname)
print(p.name)
"
end

