function toclip --wraps='xclip -selection clipboard' --description 'copy stdin to clipboard with control codes stripped'
    ansi2txt | xclip -selection clipboard
end

function toclipr --wraps='xclip -selection clipboard' --description 'alias toclip=xclip -selection clipboard'
  xclip -selection clipboard $argv
        
end
