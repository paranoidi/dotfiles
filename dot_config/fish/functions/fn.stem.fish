function fn.stem -d " Path [/etc/sudo.conf.tmp -> sudo.conf]"
    python3 -S -c "
import sys
from pathlib import Path

fname = sys.stdin.read().strip()
p = Path(fname)
print(p.stem)
"
end

