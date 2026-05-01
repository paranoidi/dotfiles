function chat --description '🧠 aichat defaults to temporary session'
  if test (count $argv) -gt 0
    aichat $argv
  else
    aichat -s
  end
end
