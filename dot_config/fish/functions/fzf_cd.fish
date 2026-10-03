# NOTES:
# - Not in use today
# - Bugs, lists files and does not cd into them? Intentional?
function fzf_cd
    set -l dir (_fzf_search_directory)
    if test -n "$dir"
        cd $dir
        commandline -f repaint
    end
end
