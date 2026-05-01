function fzf_insert_file
    set -l file (_fzf_search_directory)
    if test -n "$file"
        commandline -i -- $file
    end
end
