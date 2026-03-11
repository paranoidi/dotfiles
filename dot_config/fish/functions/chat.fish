function chat --description 'aichat defaults with session'
  if test (count $argv) -gt 0
    aichat $argv
  else
    aichat -s
  end
end
