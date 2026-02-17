function chat --description 'aichat defaults with session'
  if count $argv
    aichat $argv
  else
    aichat -s
  end
end
