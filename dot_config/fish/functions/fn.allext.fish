function fn.allext -d " Path [/etc/sudo.conf.tmp -> .conf.tmp]"
    python3 -S -c "
import sys
from pathlib import Path

fname = sys.stdin.read().strip()
p = Path(fname)
fname = p.name
if (pos := fname.find('.')) == -1:
    print("")
else:
    print(fname[pos:])
"
end

