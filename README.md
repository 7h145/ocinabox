# OpenCode in a Box

This is about running an [OpenCode](https://opencode.ai/) AI agent in an isolated containerized environment.

In modern times, coding or general AI agents do stuff on your computer. While I appreciate the help, I've serious trust issues regarding someone or something other than me having access to my system and in turn to my data.

This issue is only partially alleviated by the fact that many agents utilize some internal mechanism to limit access only to certain parts of the system running the agent (because I don't trust these either).  On the other hand, such agents need access to certain parts of your data in order to be helpful, e.g. a bunch of files or the git repository of the project you are working on.

There are several ways to go about this problem, typically involving physically separate systems, virtual machines, or containers.  This project is about the [OpenCode](https://opencode.ai/) agent running in a container with selective access to just the data you allow it to see, like e.g. this:

    ocinabox.sh ~/myprojects/thispoject ~/myprojects/thatfile

This will spawn an containerized `opencode` agent with just the specified files or directories from the host visible inside the container.

## Just a container and an `opencode` stand-in script

This thing comes in two parts: The container with OpenCode and some tooling inside and a script for running the containerized `opencode` executable with some of the hosts files or directories mounted inside the container for the agent to work with.

### The OpenCode container

A [Containerfile](https://github.com/7h145/ocinabox/blob/main/Containerfile) and an small [build script](https://github.com/7h145/ocinabox/blob/main/build.sh) which build a [Debian trixie](https://www.debian.org/releases/trixie/) based runtime environment with a somewhat sane set of tools for the agent pre-installed (but YMMV).

You can easily adjust the tooling in the container for your needs (by editing the Containerfile and run `build.sh` again) or even let the agent itself install new tools at runtime (but be aware that the containers are startet non-persistent by default).

Running the `build.sh` build script will build (or re-build) the container, always utilizing the [latest available version of OpenCode](https://github.com/anomalyco/opencode/releases) (and this is fairly efficient due to the layer caching of your container runtime).  So, just `build.sh` and restart your agents in order to update to the latest and greatest OpenCode.

### The `opencode` stand-in script

The [`ocinabox.sh` script](https://github.com/7h145/ocinabox/blob/main/ocinabox.sh) is just the containerized stand-in for the usual `opencode` command.  It does the same things as plain `opencode` but in it's own container and with one extra feature: it allows you to specify which files or directories should be visible inside the container for the agent to work on.  The wrapper script takes arguments of the form

    ocinabox.sh [SOURCE-VOLUME|HOST-DIR[:OPTIONS]...] [OPENCODE-ARGV...]

This is just a `podman run --volume` argument without the usual `:CONTAINER-DIR` part.  You can mount arbitrary files and directories in the `$PWD` of the `opencode` process running in the container (i.e. the containers `WORKDIR`) this way.

* Files are always mounted directly into `WORKDIR`, e.g.

      ocinabox.sh ~/some/file/myfile:ro

  leads to the read-only file `WORKDIR/myfile` in the container.

* Directories are always mounted as sub directories of `WORKDIR`, e.g.

      ocinabox.sh ~/some/directory/mydirectory

  leads to the directory `WORKDIR/mydirectory` in the container.

* Special case `$PWD`: If the specified directory happens to be the current `$PWD` (e.g. `.`), it is mounted directly in `WORKDIR`, e.g.

      cd ~/projects/myproject; ocinabox.sh .

  leads to the contents of `~/projects/myproject` directly visible in `WORKDIR`.

You can of course freely mix and match, e.g.

    cd ~/projects/this; ocinabox.sh . ~/projects/that:ro ~/some/file:ro

will mount ` ~/projects/this` (i.e. `$PWD`) in `WORKDIR`, `~/projects/that` read-only in `WORKDIR/that`, and the file `~/some/file` in `WORKDIR/file`.

## The Container Runtime

This thing is developed with [rootless](https://rootlesscontaine.rs/) [Podman](https://github.com/containers/podman/) in mind and [`build.sh`](https://github.com/7h145/ocinabox/blob/main/build.sh) as well as [`ocinabox.sh`](https://github.com/7h145/ocinabox/blob/main/ocinabox.sh) use Podman as default high-level container runtime.  But nothing really special happens here, any "docker lookalike" container runtime will do (e.g. [Docker](https://github.com/docker)).

Both scripts are already set up to switch the container runtime from `podman` to `docker`; it's a matter of changing two comments in each file (search for 'docker').

You should really use [rootless](https://rootlesscontaine.rs/) containers, not only but especially if you care for adversarial isolation (which is the point in this case), but it will of course run rootfull just fine.

