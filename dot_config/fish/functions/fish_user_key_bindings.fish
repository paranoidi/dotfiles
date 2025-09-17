function fish_user_key_bindings
    # Ignore CTRL-PGUP/DOWN
    for seq in '[5;5~' '[6;5~'
        bind $seq 'commandline -f repaint'  # do nothing, just redraw
    end
end
