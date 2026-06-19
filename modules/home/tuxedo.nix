# tuxedo — keyboard-driven todo.txt TUI/CLI (Rust). The durable, git-tracked
# task list lives at the repo root (todo.txt); point tuxedo at it via the
# standard TODO_FILE/DONE_FILE env vars so `todo` works from any cwd. The
# `todo-reminder` skill reads the same file to surface unfinished items.
{ pkgs, ... }:
let
  repo = "/home/homeserver/homelab";
in
{
  home.packages = [ pkgs.tuxedo ];

  home.sessionVariables = {
    TODO_FILE = "${repo}/todo.txt";
    DONE_FILE = "${repo}/done.txt";
  };

  # `todo` → open the TUI; `todo ls`, `todo add "..."` etc pass through.
  programs.fish.shellAbbrs.todo = "tuxedo";
}
