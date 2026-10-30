function o --wraps=xdg-open --description 'alias o=xdg-open'
    if not type -q xdg-open
        echo "🚫 xdg-open is not installed"
        return 1
    end
    if test (count $argv) -eq 0
        set argv .
    end
    xdg-open $argv
end
