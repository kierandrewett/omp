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

# Install the binary into build/prefix, a folder laid out like an installed system (builds the binary if dist/ has none).
prefix:
    scripts/install-prefix.sh

# Show the packages pkgsmith would write from the prefix, and what each one carries.
plan:
    scripts/package.sh plan
    scripts/package.sh files

# Write the packages to dist/packages.
package:
    scripts/package.sh build

# Install every package in a throwaway container of its distro and run omp. Needs podman or docker.
smoke-packages:
    scripts/smoke-packages.sh

clean:
    git -C upstream worktree prune
    rm -rf build dist
