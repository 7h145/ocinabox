# OpenCode in a Box

This is about running an [OpenCode AI agent](https://opencode.ai/) ([GitHub](https://github.com/anomalyco/opencode), [npm](https://www.npmjs.com/package/opencode-ai)) in an isolated containerized environment.

These days, coding and general-purpose AI agents do things on your computer. While I appreciate the help, I have serious trust issues with someone or something other than me having access to my system and, in turn, to my data.

This issue is only partially alleviated by the fact that many agents use some internal mechanism to limit access to certain parts of the system running the agent (because I don't trust these either).  On the other hand, such agents need access to some of your data in order to be helpful, e.g. a bunch of files or the git repository of the project you are working on.

There are several ways to address this problem, typically involving physically separate systems, virtual machines, or containers.  This project is about the [OpenCode](https://opencode.ai/) agent running in a container with selective access to just the data you allow it to see, for example:

    ocinabox.sh ~/myprojects/thisproject ~/myprojects/thatfile

This will spawn a containerized `opencode` agent with just the specified files or directories from the host visible inside the container.

Security note: This is a containerized setup, but not magic.  Anything you mount into the container is visible to code running there, and it uses the host network namespace (`--network=host`) by default.  Only mount what you actually want to share, use `:ro` where possible.

There is a technically very similar [version of this project for the pi coding agent](https://github.com/7h145/piinabox); see [Opinions](#opinions) below if you want my rationale for having a look at that.

## Just a container and an `opencode` stand-in script

This project comes in two parts: The container with OpenCode and some tooling inside and a script for running the containerized `opencode` executable with some of the host files or directories mounted inside the container for the agent to work with.

### The OpenCode container

A [Containerfile](Containerfile) and a small [build script](build.sh) build a [Debian trixie](https://www.debian.org/releases/trixie/) based [Node.js](https://nodejs.org/) runtime environment with the [opencode-ai npm package](https://www.npmjs.com/package/opencode-ai) and a somewhat sane set of pre-installed tools for the agent pre-installed (but YMMV).

You can easily adjust the tooling in the container image for your needs (by editing the Containerfile and running `build.sh` again) or even let the agent itself install new tools at runtime (but be aware that the containers are not persistent by default).

Running the `build.sh` build script will build (or re-build) the container image, using the [latest version of OpenCode](https://github.com/anomalyco/opencode/releases) by default. This is fairly efficient due to the layer caching of your container runtime. To update to the latest version, run `build.sh` and restart your agents.

Tip: to rebuild the image from scratch using a fresh base image, run:

    build.sh --no-cache --pull=always

### The `opencode` stand-in script

The [`ocinabox.sh` script](ocinabox.sh) is the containerized stand-in for the usual `opencode` command.  It does the same things as plain `opencode` but in its own container and with one extra feature: it allows you to specify which files or directories should be visible inside the container for the agent to work on.  The wrapper script takes arguments of the form

    ocinabox.sh [SOURCE-VOLUME|HOST-DIR[:OPTIONS]...] [OPENCODE-ARGV...]

Each leading argument is treated like a `podman run --volume` argument without the usual `:CONTAINER-DIR` part.  You can mount arbitrary files and directories in the `$PWD` of the `opencode` process running in the container (i.e. the container's `WORKDIR`) this way.

* Files are always mounted directly into `WORKDIR`, e.g.

      ocinabox.sh ~/some/file/myfile:ro

  leads to the read-only file `WORKDIR/myfile` in the container.

* Directories are always mounted as subdirectories of `WORKDIR`, e.g.

      ocinabox.sh ~/some/directory/mydirectory

  leads to the directory `WORKDIR/mydirectory` in the container.

* Special case `$PWD`: If the specified directory happens to be the current `$PWD` (e.g. `.`), it is mounted directly in `WORKDIR`, e.g.

      cd ~/projects/myproject; ocinabox.sh .

  leads to the contents of `~/projects/myproject` directly visible in `WORKDIR`.

You can of course freely mix and match, e.g.

    cd ~/projects/this; ocinabox.sh . ~/projects/that:ro ~/some/file:ro

will mount `~/projects/this` (i.e. `$PWD`) in `WORKDIR`, `~/projects/that` read-only in `WORKDIR/that`, and the file `~/some/file` in `WORKDIR/file`.

Further command line arguments are passed through to `opencode` after the leading mount specifications, e.g.

    ocinabox.sh .:ro run 'explain this codebase'

## Notes

OpenCode may update or migrate its own configuration when versions change.  A read-only host configuration is safest, but can break such upgrades; a read/write mount is more compatible, but lets the container modify the host configuration.

`ocinabox.sh` therefore defaults to Podman's overlay volume mode (`:O`) for `$XDG_CONFIG_HOME/opencode`.  The host configuration is visible and writable from OpenCode's point of view, but changes are written to a temporary overlay and discarded with the container.  Change the setting to `rw` if you want OpenCode configuration changes to persist on the host.

`:O` is Podman-specific.  Use `ro` or `rw` when running with Docker.

## The Container Runtime

This thing is developed with [rootless](https://rootlesscontaine.rs/) [Podman](https://github.com/containers/podman/) in mind.  [`build.sh`](build.sh) and [`ocinabox.sh`](ocinabox.sh) use Podman as the default high-level container runtime, but nothing really special happens here; any "docker lookalike" container runtime will do (e.g. [Docker](https://github.com/docker)).

Both scripts are already set up to switch the container runtime from `podman` to `docker`; it's a matter of changing two comments in each file (search for 'docker').

You should really use [rootless](https://rootlesscontaine.rs/) containers, especially if you care about adversarial isolation (which is the point in this case), but it will of course run rootful just fine.


## Opinions

[OpenCode](https://opencode.ai/) was the first AI agent thing that "clicked for me" - that really helped me get stuff done.  I still think it's a great tool, and I have great respect for the people building it.  That said, it has developed into a veritable kitchen sink of features that are somewhat loosely related to being a coding agent (incidentally, this is much the same direction [Claude Code](https://github.com/anthropics/claude-code) has taken).  The pace of development also seems to exceed the time it takes to do actual software architecture work (you know - the part the AIs don't do that well as of the time of this writing).

And then there are various technical considerations, some of them affecting the containerization (which is critical for me, [see trust issues above](#opencode-in-a-box)).  One example is [this bug](https://github.com/anomalyco/opencode/issues/27786) ([which has](https://github.com/anomalyco/opencode/issues/18633) [some history](https://github.com/anomalyco/opencode/issues/21966)).

See, OpenCode expects its configuration to be readable and writable (which is sort of fine; running it in a container is my problem, not theirs), but at the same time it dumps >50 MB of code into the configuration directory ([where it does not belong](https://specifications.freedesktop.org/basedir/latest/)).  I can work around this, but even just documenting such foolishness in a way casual users can deal with is kind of useless work.  And the best part: since [OpenCode's release cadence is absurd](https://github.com/anomalyco/opencode/releases), this might be fixed while I'm typing.

Let me paraphrase Mario Zechner of https://pi.dev/ fame here: [slow the fuck down](https://mariozechner.at/posts/2026-03-25-thoughts-on-slowing-the-fuck-down/) (really, it's worth a read).
And speaking of `pi`: have a look at [piinabox](https://github.com/7h145/piinabox)...

