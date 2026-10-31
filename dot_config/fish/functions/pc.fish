function pc --wraps=pc --description 'pc, then cd to its active panel directory'
    set -l tmp (mktemp)
    command pc --cwd-file=$tmp $argv
    set -l dir (cat $tmp)
    rm -f $tmp
    if test -n "$dir"; and test "$dir" != "$PWD"
        cd $dir
    end
end
