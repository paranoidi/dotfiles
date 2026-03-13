function ports --description 'List listening ports'
  lsof -iTCP -sTCP:LISTEN -P -n
end
