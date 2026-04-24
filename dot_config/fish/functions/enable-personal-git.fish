function enable-personal-git --description 'Enable personal git account by writing ~/.gitconfig.local'
    if test -e ~/.gitconfig.local
        echo 'Warning: ~/.gitconfig.local already exists; aborting'
        return 1
    end

    begin
        echo '[user]'
        echo '   email = marko.koivusalo@gmail.com'
        echo '   name = paranoidi'
    end > ~/.gitconfig.local

    echo 'Wrote ~/.gitconfig.local'
end