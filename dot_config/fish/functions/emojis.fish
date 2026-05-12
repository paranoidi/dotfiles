function emojis --description '🎉 Print terminal-friendly emojis for copy and paste'
    set single_width ✅ �� ✨ 🎉 ❌ 🚫 🔧 🚀 🔥 🔑 🔍 🕓 ⏳ 📦 💥 💾 📡 🌐 📥 🗂️ 📁 📋 📃 📖 📝 📜 📊 🏠 🤖 🧠 🎬 🚧 🎮 🍺 💻 🧱 🚪 📏 🦀 🐳 🐹 🐪 🐟 🐍 🐞 💎 🔀 💩 🔗 🧪 🔐 🧰 🧹 🧊 🧵 🧭 🔴 🟠 🟡 🟢 🔵 🟣 ⚫
    set double_width ℹ️ ⚠️ ✏️ 🗑️ 🛠️ ☢️ ☠️ ⏭️

    printf '%s\n' 'Terminal-friendly emojis for copy and paste'
    printf '%s\n' ''
    printf '%s\n' 'Single-cell:'
    if set -q argv[1]
        for emoji in $single_width
            set str "$emoji$argv[1]"
            echo $str
        end
    else
        printf '%s\n' (string join ' ' $single_width)
    end
    printf '%s\n' ''
    printf '%s\n' 'Two-character symbols'
    printf '%s\n' 'Two spaces in gnome-terminal. One in tmux.'
    if set -q argv[1]
        for emoji in $double_width
            set str "$emoji$argv[1]"
            echo $str
        end
    else
        printf '%s\n' (string join ' ' $double_width)' '
    end
    printf '%s\n' ''
    printf '%s\n' 'Iconic emojis:'
    printf '%s\n' ' 󰉍 󰲂 󱍙 󰉏         󰇚'
    printf '%s\n' ''
    printf '%s\n' 'Markers:'
    printf '%s\n' '○ ● ◇ ◆'
end
