# dotfiles-dotenvxx profile

This directory is the local home for the `dotfiles-dotenvxx` secrets profile.

## Location

- Encrypted env file: `~/.config/dotfiles/dotfiles-dotenvxx/.env`
- Optional local key file: `~/.config/dotfiles/dotfiles-dotenvxx/.env.keys`

## Shell helpers

```zsh
dotfiles_dotenvxx_encrypt   # encrypt or rotate the profile file with dotenvx
dotfiles_dotenvxx_run -- <cmd>  # run a command with the profile loaded
aws-login                   # prefers dotfiles-dotenvxx, falls back to Doppler
aws-login-doppler           # force the legacy Doppler-backed flow
```

## Notes

- Keep plaintext secrets out of git.
- Use `dotenvx encrypt -f ~/.config/dotfiles/dotfiles-dotenvxx/.env` when updating values.
- The legacy Doppler path still exists for machines that have not migrated yet.
