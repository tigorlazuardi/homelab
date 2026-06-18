{
  programs.lazygit = {
    enable = true;

    settings = {
      gui = {
        showIcons = true;
        nerdFontsVersion = "3";
        theme = {
          lightTheme = false;
          activeBorderColor = [
            "green"
            "bold"
          ];
          inactiveBorderColor = [ "white" ];
          selectedLineBgColor = [ "reverse" ];
        };
        showFileTree = true;
        showRandomTip = false;
        showCommandLog = false;
        splitDiff = "auto";
      };

      git = {
        pager = {
          colorArg = "always";
          pager = "delta --dark --paging=never";
        };
        commit = {
          signOff = false;
          autoWrapCommitMessage = true;
          autoWrapWidth = 72;
        };
        merging = {
          manualCommit = false;
          args = "";
        };
        log = {
          order = "topo-order";
          showGraph = "always";
        };
        mainBranches = [
          "main"
          "master"
        ];
        skipHookPrefix = "WIP";
        autoFetch = true;
        autoRefresh = true;
        branchLogCmd = "git log --graph --color=always --abbrev-commit --decorate --date=relative --pretty=medium {{branchName}} --";
      };

      os = {
        editPreset = "nvim";
      };

      refresher = {
        refreshInterval = 10;
        fetchInterval = 60;
      };

      confirmOnQuit = false;
      quitOnTopLevelReturn = true;

      keybinding = {
        universal = {
          quit = "q";
          quit-alt1 = "<c-c>";
          return = "<esc>";
          togglePanel = "<tab>";
          prevPage = "<c-u>";
          nextPage = "<c-d>";
          scrollUpMain = "<c-u>";
          scrollDownMain = "<c-d>";
          gotoTop = "<";
          gotoBottom = ">";
          prevBlock = "<left>";
          nextBlock = "<right>";
          nextMatch = "n";
          prevMatch = "N";
          new = "n";
          edit = "e";
          openFile = "o";
          copyToClipboard = "<c-o>";
          submitEditorText = "<enter>";
          undo = "u";
          redo = "<c-r>";
        };
      };

      # Custom commands
      customCommands = [
        {
          key = "C";
          command = "git commit";
          context = "files";
          output = "terminal";
          description = "Commit with editor";
        }
        {
          key = "P";
          command = "git push --force-with-lease";
          context = "localBranches";
          loadingText = "Force pushing (safely)...";
          description = "Force push with lease";
        }
      ];
    };
  };
}
