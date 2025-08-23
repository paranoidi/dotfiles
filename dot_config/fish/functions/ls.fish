function ls --wraps='eza --icons --no-quotes' --description 'alias ls=eza --icons --no-quotes'
    if not set -q CURSOR_AGENT
        eza --icons --no-quotes --color=always $argv
    else
        command ls $argv
    end
end
