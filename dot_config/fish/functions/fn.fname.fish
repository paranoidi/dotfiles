function fn.fname -d " Path [/etc/sudo.conf -> sudo]"
    python3 -S -c "
import sys
from pathlib import Path

fname = sys.stdin.read().strip()
p = Path(fname)
fname = p.name
if (pos := fname.find('.')) == -1:
    print(fname)
else:
    print(fname[:pos])
"
end

