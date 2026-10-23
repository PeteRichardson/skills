# Link each skill in my repo into ~/.claude/skills, and remove links to skills that were deleted
skills-link() {
  rm -f ~/.claude/skills/*(N-@)                 # (N-@) matches broken symlinks only
  local f
  for f in ~/projects/skills/*/SKILL.md(N); do
    ln -sfn "${f:h}" ~/.claude/skills/"${f:h:t}"
  done
}

# Update everything with one command
skills-update() {
  # update personal skills in PeteRichardson/skills repo
  # and re-establish symlinks in ~/.claude/skills
  git -C ~/projects/skills pull --ff-only || return
  skills-link
  # update mattpocock skills
  npx skills@latest update -g
}
