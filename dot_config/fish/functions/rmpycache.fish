function rmpycache --description 'Delete all python cachefiles recursively'
    find . -type d -name '__pycache__' -print0 | xargs -0 -I {} rm -rv {}
end
