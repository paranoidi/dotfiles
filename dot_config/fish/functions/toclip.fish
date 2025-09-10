function toclip --wraps='xclip -selection clipboard' --description 'alias toclip=xclip -selection clipboard'
  xclip -selection clipboard $argv
        
end
