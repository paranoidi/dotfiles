function lt --wraps='ll -TL 3' --description 'alias lt=ll -TL 3'
  ll --git-ignore -TL 3 $argv
end
