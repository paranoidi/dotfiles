function lln --wraps=ls --wraps='eza -l -snew' --description 'alias ll=eza -l -snew'
    eza -l -snew --time-style long-iso --color=always --icons --no-quotes --git $argv
end
