function toclip --wraps='xclip -selection clipboard' --description '📋 Copy stdin or file to clipboard without ANSI'
    if test (count $argv) -gt 0
        ansi2txt < $argv[1] | xclip -selection clipboard
    else
        ansi2txt | xclip -selection clipboard
    end
    notify-send -t 1500 "Copied"
end

function toclipr --wraps='xclip -selection clipboard' --description 'alias toclip=xclip -selection clipboard'
    xclip -selection clipboard $argv
    notify-send -t 1500 "Copied"
end
