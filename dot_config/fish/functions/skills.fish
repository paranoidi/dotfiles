function skills --description "🧠 Run skills with latest Node via nvm"
    nvm use latest >/dev/null 2>&1
    if test $status -ne 0
        _spinner --fallback-prefix "🌐" "Installing latest node via nvm …" nvm install latest
        if test $status -ne 0
            echo "❌ failed to install latest Node with nvm" >&2
            return 1
        end
    end

    set -l npx_exec (command --search npx)
    if test -z "$npx_exec"
        echo "❌ npx executable not found after running 'nvm use latest'" >&2
        return 127
    end

    command $npx_exec --yes skills $argv
end
