# Link each skill into ~/.claude/skills, and remove links to skills that were deleted.
# The real skill folders live in two roots that other agents (Hermes, Pi) read directly:
#   ~/.agents/skills   - skills installed by `npx skills` (mattpocock and others)
#   ~/projects/skills  - my own skills (this repo)
# Claude Code has no setting for extra skill roots, so only ~/.claude/skills holds symlinks.
# My repo is linked last, so its skill wins when both roots have the same name.
skills-link() {
  rm -f ~/.claude/skills/*(N-@)                 # (N-@) matches broken symlinks only
  local f dest
  for f in ~/.agents/skills/*/SKILL.md(N) ~/projects/skills/*/SKILL.md(N); do
    dest=~/.claude/skills/"${f:h:t}"
    if [[ -d $dest && ! -L $dest ]]; then
      # ln -sfn would put the link INSIDE a real folder; do not do that
      print -u2 "skills-link: $dest is a real folder, not a link; skipped ${f:h}"
      continue
    fi
    ln -sfn "${f:h}" "$dest"
  done
}

# Update everything with one command
skills-update() {
  # update personal skills in PeteRichardson/skills repo
  git -C ~/projects/skills pull --ff-only || return
  # update mattpocock skills (into ~/.agents/skills)
  npx skills@latest update -g
  # re-establish symlinks in ~/.claude/skills (after the update, so my repo wins name clashes)
  skills-link
}
