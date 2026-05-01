function fn.ext -d " Path [/etc/sudo.conf -> .conf]"
    python3 -S -c "
import sys
from pathlib import Path

fname = sys.stdin.read().strip()
p = Path(fname)
print(p.suffix)
"
end

