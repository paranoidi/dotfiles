function getcol -d "Split the input on whitespace and print the column indicated"
    awk '{print $'$argv[1]'}'
end
