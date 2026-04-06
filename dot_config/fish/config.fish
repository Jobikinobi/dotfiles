
# >>> conda initialize >>>
# !! Contents within this block are managed by 'conda init' !!
if test -f /Users/jth/micromamba/bin/conda
    eval /Users/jth/micromamba/bin/conda "shell.fish" "hook" $argv | source
else
    if test -f "/Users/jth/micromamba/etc/fish/conf.d/conda.fish"
        . "/Users/jth/micromamba/etc/fish/conf.d/conda.fish"
    else
        set -x PATH "/Users/jth/micromamba/bin" $PATH
    end
end
# <<< conda initialize <<<

