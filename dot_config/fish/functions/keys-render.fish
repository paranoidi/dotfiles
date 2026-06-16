function keys-render --description "Render a keys file with color and alignment"
    set -l file $argv[1]
    set -l cols (if set -q FZF_PREVIEW_COLUMNS; echo $FZF_PREVIEW_COLUMNS; else; tput cols; end)

    set -l b (set_color brblack) # borders + hints
    set -l T (set_color --bold blue) # section title (bold)
    set -l S (set_color cyan) # shortcut keys
    set -l n (set_color normal) # reset

    set -l lines
    while read -l line
        set -a lines "$line"
    end <$file

    # Find section header positions
    set -l header_pos
    for i in (seq (count $lines))
        string match -qr '^## ' -- $lines[$i]; and set -a header_pos $i
    end

    if test (count $header_pos) -eq 0
        cat $file
        return 0
    end

    set -a header_pos (math (count $lines) + 1) # sentinel

    for s in (seq 1 (math (count $header_pos) - 1))
        set -l start $header_pos[$s]
        set -l end_pos (math $header_pos[(math $s + 1)] - 1)
        set -l title (string replace -r '^## ' '' -- $lines[$start])

        set -l actions
        set -l shortcuts
        set -l hints

        if test $end_pos -ge (math $start + 1)
            for i in (seq (math $start + 1) $end_pos)
                set -l line $lines[$i]
                test -z "$line"; and continue
                set -l parts (string split '|' -- $line)
                set -a actions $parts[1]
                if test (count $parts) -ge 2
                    set -a shortcuts $parts[2]
                else
                    set -a shortcuts ""
                end
                if test (count $parts) -ge 3
                    set -a hints $parts[3]
                else
                    set -a hints ""
                end
            end
        end

        # Compute column widths
        set -l w1 0
        for a in $actions
            set -l l (string length -- "$a")
            if test $l -gt $w1
                set w1 $l
            end
        end
        set -l w2 0
        for sh in $shortcuts
            set -l l (string length -- "$sh")
            if test $l -gt $w2
                set w2 $l
            end
        end

        # Show hints only if they exist and space permits
        set -l show_hints 0
        for h in $hints
            if test -n "$h"
                set show_hints 1
                break
            end
        end
        if test $show_hints -eq 1 -a $cols -lt (math $w1 + 3 + $w2 + 13)
            set show_hints 0
        end

        test $s -gt 1; and echo

        # Dynamic header
        set -l sep_len (math $cols - (string length -- "$title") - 4)
        if test $sep_len -lt 2
            set sep_len 2
        end
        printf "%s~~ %s%s%s %s%s\n" $b $T $title $b (string repeat -n $sep_len '~') $n

        for i in (seq (count $actions))
            set -l a $actions[$i]
            set -l sh $shortcuts[$i]
            set -l h $hints[$i]
            if test $show_hints -eq 1 -a -n "$h"
                printf "%-*s %s %s %s%-*s%s  %s(%s)%s\n" $w1 "$a" $b $n $S $w2 "$sh" $n $b "$h" $n
            else if test -n "$sh"
                printf "%-*s %s %s %s%s%s\n" $w1 "$a" $b $n $S "$sh" $n
            else
                printf "%s\n" "$a"
            end
        end
    end
end
