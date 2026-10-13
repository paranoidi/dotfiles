# ponytail: checked once at autoload, not per call
if functions -q z
    function cd --wraps=z --description 'alias cd=z'
        z $argv
    end
else
    # zoxide not available: use fish's stock cd (keeps dirprev/cdh history)
    source $__fish_data_dir/functions/cd.fish
end
