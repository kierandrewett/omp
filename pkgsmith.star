# The packages of omp. pkgsmith builds nothing: scripts/install-prefix.sh lays the binary out in a prefix, and this script
# describes the packages made from that prefix. scripts/package.sh runs pkgsmith on it with the arguments below.
#
#   scripts/install-prefix.sh      # build/prefix/usr/bin/omp and the notice
#   scripts/package.sh plan        # which packages, which file names
#   scripts/package.sh files       # what each package carries
#   scripts/package.sh             # write them to dist/packages
#
# Arguments (pkgsmith build --build-arg NAME=VALUE), all set by scripts/package.sh:
#   VERSION  the upstream version, for example 18.14.2
#   RELEASE  the fork revision from the `revision` file, so 18.14.2 revision 2 is omp-18.14.2-2 in a deb or rpm and
#            sorts above 18.14.2-1 and below 18.14.3-1
#   ARCH     amd64 or arm64: the architecture of the binary in the prefix, not of the machine that runs pkgsmith
#   LIBC     glibc or musl: the C library of the binary in the prefix
# scripts/package.sh reads ARCH and LIBC from the ELF headers of the binary, so they cannot disagree with the files.

VERSION = arg("VERSION")
RELEASE = arg("RELEASE")
if not VERSION or not RELEASE:
    fail("pass --build-arg VERSION=... and --build-arg RELEASE=...; scripts/package.sh does this")

LIBC = arg("LIBC")
if LIBC not in ["glibc", "musl"]:
    fail("pass --build-arg LIBC=glibc or musl for the binary in the prefix; scripts/package.sh does this")

common = {
    "name": "omp",
    "version": VERSION,
    "release": RELEASE,
    "description": """Oh My Pi, a terminal coding agent (patched build)
A build of can1357/oh-my-pi with a small set of patches. The program is one self-contained executable.""",
    "maintainer": "Kieran Drewett <kieran@drewett.dev>",
    "homepage": "https://github.com/kierandrewett/omp",
    # `license` is left out on purpose. The packages hold oh-my-pi, which is MIT (see /usr/share/licenses/omp/NOTICE.md),
    # plus patches that have no licence of their own yet. Set it here once that is decided.
}
if arg("ARCH"):
    common["arch"] = arg("ARCH")

# The names of the libraries the binary links to, per distro. `readelf -d usr/bin/omp | grep NEEDED` lists them: libc,
# libm, libdl and libpthread, which one package provides on every distro. A musl binary also needs libstdc++ and libgcc,
# the same two that upstream installs in its Alpine smoke test.
DEPENDS = {
    "glibc": {"rpm": ["glibc"], "deb": ["libc6"], "archlinux": ["glibc"]},
    "musl": {"apk": ["libstdc++", "libgcc"]},
}

# The formats follow the C library of the binary. A glibc binary does not run on Alpine, which has musl, so the glibc
# prefix writes no apk. A musl binary does not run on the glibc distros, so a musl prefix writes only the apk. Build the
# musl prefix with upstream's linux-musl target (see README.md). Until one exists no apk is written.
FORMATS = {
    "glibc": ["rpm", "deb", "archlinux", "tar"],
    "musl": ["apk"],
}

for fmt in FORMATS[LIBC]:
    package(fmt, depends = DEPENDS[LIBC].get(fmt, []), **common)
