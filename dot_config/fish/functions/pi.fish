function pi --description "🧠 Run pi with latest Node via nvm"
    nvm use latest >/dev/null 2>&1
    if test $status -ne 0
        echo "⬇️  Node 'latest' not installed, running nvm install latest …" >&2
        nvm install latest >/dev/null
        if test $status -ne 0
            echo "❌ failed to install latest Node with nvm" >&2
            return 1
        end
    end

    set -l pi_exec (command --search pi)
    if test -z "$pi_exec"
        echo "❌ pi executable not found after running 'nvm use latest'" >&2
        return 127
    end

    command $pi_exec $argv
end
