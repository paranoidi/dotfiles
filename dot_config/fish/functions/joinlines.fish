function joinlines --argument sep -d "Join the input lines with a separator"
    python3 -S -c "
import sys

sep = '$sep'

lines = sys.stdin.read().splitlines()
print(sep.join(lines))

# for line in sys.stdin:
    # line = line.rstrip('\r\n')
    # print(line + sep, end='')
# print()
"
end
