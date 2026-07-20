function colours --description '🎨 Print a 256-colour terminal background palette'
    for i in (seq 0 255)
        printf "\e[48;5;%sm%3d\e[0m " $i $i
        if test (math "($i + 1) % 16") -eq 0
            echo
        end
    end
    echo
end
