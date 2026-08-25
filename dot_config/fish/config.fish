
# >>> conda initialize >>>
# !! Contents within this block are managed by 'conda init' !!
if test -f $HOME/micromamba/bin/conda
    eval $HOME/micromamba/bin/conda "shell.fish" "hook" $argv | source
else if test -f "$HOME/micromamba/etc/fish/conf.d/conda.fish"
    . "$HOME/micromamba/etc/fish/conf.d/conda.fish"
else if test -d "$HOME/micromamba/bin"
    set -x PATH "$HOME/micromamba/bin" $PATH
end
# <<< conda initialize <<<
