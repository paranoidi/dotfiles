function ll --wraps=ls --wraps='eza -l' --description 'alias ll=eza'
  eza -l --time-style long-iso --color=always --icons --no-quotes --git $argv
end
