function mkv2mp4 --description "🎬 Convert mkv to mp4"
    if not command -q ffmpeg
        echo "❌ ffmpeg is required but not installed or not in PATH" >&2
        return 127
    end

    if test (count $argv) -eq 0
        echo "Usage: mkv2mp4 <filename>"
        return 1
    end

    set inputfile $argv[1]
    set suffix (string match -r '\.[^.]+$' $inputfile)
    set basename (string replace $suffix "" $inputfile)
    set outputfile $basename.mp4

    ffmpeg -i $inputfile -codec copy $outputfile
end

