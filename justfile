# Patch series for the omp fork of can1357/oh-my-pi. See README.md.

default:
    @just --list

# Move the upstream submodule to the newest stable tag (or TAG) and re-apply the series.
update tag="":
    scripts/update-upstream.sh {{tag}}

# Create work/src with every patch applied as a commit.
work:
    scripts/work.sh --reset

# Write the commits in work/src back to patches/ and the series.
export:
    scripts/export.sh

# Build dist/omp-linux-<arch> from upstream plus the series.
build:
    scripts/build.sh

# Install dist/omp-linux-<arch> as ~/.local/bin/omp.
install:
    scripts/install-local.sh

clean:
    git -C upstream worktree prune
    rm -rf build dist
