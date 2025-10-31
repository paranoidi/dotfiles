function rmhist --description "Remove commands matching a regex from Fish history"
    argparse 's/silent' -- $argv
    or return
    
    if test (count $argv) -eq 0
        echo "Usage: rmhist [-s|--silent] <regex>"
        return 1
    end
    
    set -l regex $argv[1]
    set -l history_file ~/.local/share/fish/fish_history
    
    if not test -f "$history_file"
        echo "History file not found at $history_file"
        return 1
    end
    
    set -l temp_file (mktemp)
    set -l skip 0
    set -l current_cmd ""
    set -l removed_count 0
    
    while read -l line
        # Check if this is a command line
        if string match -q -- "- cmd: *" "$line"
            # Extract the command
            set current_cmd (string replace -- "- cmd: " "" "$line")
            
            # Check if it matches the regex
            if string match -qr -- "$regex" "$current_cmd"
                set skip 1
                set removed_count (math $removed_count + 1)
                if not set -q _flag_silent
                    echo "Removed: $current_cmd"
                end
            else
                set skip 0
                echo "$line" >> $temp_file
            end
        else
            # This is a continuation line (like "  when: ...")
            if test $skip -eq 0
                echo "$line" >> $temp_file
            end
        end
    end < $history_file
    
    mv $temp_file $history_file
    
    if not set -q _flag_silent
        echo ""
        echo "Removed $removed_count history entries matching '$regex'"
    end
    
    # Reload history in current session
    history --merge
end                                                                                               

