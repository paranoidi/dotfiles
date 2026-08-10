function resolve-conflicts --description '🧠 Ask claude to resolve merge conflicts'
    claude "Resolve existing git merge or rebase conflicts. If this is a rebase continue it after resolving. If this is not a rebase execute 'git add -u && git commit --no-edit' after resolving. If this project has taskfile.yml present with task test run that before acceptin resolve."
end
