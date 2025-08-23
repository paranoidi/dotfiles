function bat --description 'use right bat'
    if type -q batcat
        batcat $argv
    else
        bat $argv
    end
end
