{
  programs.git = {
    enable = true;

    settings = {
      user = {
        name = "Tigor Hutasuhut";
        email = "tigor.hutasuhut@gmail.com";
      };

      # Core settings
      core = {
        autocrlf = "input"; # Convert CRLF to LF on commit (cross-platform friendly)
        whitespace = "fix"; # Fix whitespace issues
        editor = "nvim";
      };

      # Better default branch name
      init.defaultBranch = "main";

      # Pull behavior
      pull = {
        rebase = true; # Rebase instead of merge on pull
        default = "current"; # Pull current branch from remote
      };

      # Push behavior
      push = {
        autoSetupRemote = true; # Auto setup remote tracking on first push
        default = "current"; # Push current branch to same name on remote
      };

      # Fetch behavior
      fetch = {
        prune = true; # Remove remote-tracking refs that no longer exist
        prunetags = true; # Remove tags that no longer exist on remote
      };

      # Rebase settings
      rebase = {
        autoStash = true; # Auto stash before rebase and pop after
        autoSquash = true; # Auto squash fixup commits
      };

      # Merge settings
      merge = {
        conflictstyle = "zdiff3"; # Show common ancestor in conflicts
        ff = "only"; # Only allow fast-forward merges (safer)
      };

      # Diff settings
      diff = {
        algorithm = "histogram"; # Better diff algorithm
        colorMoved = "default"; # Highlight moved lines
        colorMovedWS = "allow-indentation-change";
      };

      # Better logs
      log = {
        abbrevCommit = true; # Short commit hashes
        follow = true; # Follow file renames
      };

      # Branch settings
      branch = {
        autoSetupMerge = "always";
        sort = "-committerdate"; # Sort branches by recent commits
      };

      # Tag settings
      tag.sort = "-version:refname"; # Sort tags by version

      # Rerere (reuse recorded resolution)
      rerere.enabled = true; # Remember conflict resolutions

      # Column output for branch/tag lists
      column.ui = "auto";

      # Credential helper
      credential.helper = "store"; # Store credentials (consider using libsecret on desktop)

      # URL shortcuts
      url = {
        "git@github.com:" = {
          insteadOf = "gh:";
        };
        "git@gitlab.com:" = {
          insteadOf = "gl:";
        };
      };

      # Aliases
      alias = {
        # Shortcuts
        co = "checkout";
        br = "branch";
        ci = "commit";
        st = "status -sb";
        sw = "switch";

        # Logging
        lg = "log --oneline --graph --decorate";
        ll = "log --oneline -20";
        last = "log -1 HEAD --stat";

        # Undo helpers
        unstage = "reset HEAD --";
        uncommit = "reset --soft HEAD~1";
        amend = "commit --amend --no-edit";
        discard = "checkout --"; # Discard changes in specific files (git discard file.txt)

        # Diff shortcuts
        df = "diff";
        dfs = "diff --staged";

        # Branch management
        brd = "branch -d";
        brD = "branch -D";
        merged = "branch --merged";
        unmerged = "branch --no-merged";

        # Stash shortcuts
        ss = "stash";
        sp = "stash pop";
        sl = "stash list";

        # Clean shortcuts
        pristine = "!git reset --hard && git clean -dfx";

        # Interactive rebase shortcut
        ri = "rebase -i";

        # Show contributors
        contributors = "shortlog -sn --no-merges";
      };
    };

    # Ignore patterns (global)
    ignores = [
      # OS files
      ".DS_Store"
      "Thumbs.db"

      # Editor files
      "*.swp"
      "*.swo"
      "*~"
      ".idea/"
      ".vscode/"
      "*.sublime-*"

      # Environment files
      ".env.local"
      ".direnv/"

      # Build artifacts
      "node_modules/"
      "__pycache__/"
      "*.pyc"
      ".cache/"
      "dist/"
      "build/"
      "target/"

      # Logs
      "*.log"
      "npm-debug.log*"
    ];
  };

  # Delta for better diffs
  programs.delta = {
    enable = true;
    enableGitIntegration = true;
    options = {
      navigate = true;
      line-numbers = true;
      syntax-theme = "Dracula";
      side-by-side = false;
    };
  };
}
