function len -d "Length of a string"
    python3 -S -c "
import sys

s = sys.stdin.read().rstrip('\r\n')
print(len(s))
"
end
