function n --wraps=nemo --description 'Open nemo file manager in the background'
    if not type -q nemo
        echo "🚫 nemo is not installed"
        return 1
    end
    if test (count $argv) -eq 0
        set argv .
    end
    nemo $argv & disown
end
