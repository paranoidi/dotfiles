function man --wraps man --description "Display man pages with bat"
    command man $argv | bat -l man --style=plain
end
