function skills --description "🧠 Run skills with latest Node via nvm"
    nvm use latest >/dev/null
    set -l nvm_status $status
    if test $nvm_status -ne 0
        echo "❌ failed to activate latest Node with nvm" >&2
        return $nvm_status
    end

    set -l npx_exec (command --search npx)
    if test -z "$npx_exec"
        echo "❌ npx executable not found after running 'nvm use latest'" >&2
        return 127
    end

    command $npx_exec --yes skills $argv
end
