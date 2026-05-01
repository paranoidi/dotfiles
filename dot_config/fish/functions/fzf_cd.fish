function fzf_cd
    set -l dir (_fzf_search_directory)
    if test -n "$dir"
        cd $dir
        commandline -f repaint
    end
end
