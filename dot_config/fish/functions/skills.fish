function skills --description "🧠 Run skills with latest Node via nvm"
    nvm use latest >/dev/null 2>&1
    if test $status -ne 0
        echo "⬇️  Node 'latest' not installed, running nvm install latest …" >&2
        nvm install latest >/dev/null
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
