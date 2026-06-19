{
  home.file.".golangci.yml".text = /* yaml */ ''
    version: "2"

    linters:
      default: none
      enable:
        # performance
        - prealloc
        - noctx
        - bodyclose

        # security
        - gosec

        # bugs / correctness
        - govet
        - staticcheck
        - ineffassign
        - errcheck
        - sqlclosecheck
        - rowserrcheck
        - durationcheck
        - nilerr
        - nilnil

      settings:
        gosec:
          excludes: []
        govet:
          enable-all: true
  '';
}
