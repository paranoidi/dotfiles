function toclip --wraps='xclip -selection clipboard' --description '📋 Copy stdin to clipboard without ANSI'
    ansi2txt | xclip -selection clipboard
    notify-send -t 1500 "Copied"
end

function toclipr --wraps='xclip -selection clipboard' --description 'alias toclip=xclip -selection clipboard'
    xclip -selection clipboard $argv
    notify-send -t 1500 "Copied"
end
