function weather --description '🌦️ Check the weather in Jyväskylä'
  curl -s "wttr.in/jyvaskyla" | head -n -3 | tail -n +2
end
