
&nbsp;<a href="https://github.com/robot-wranglers/compose.mk/actions/workflows/cmk-demos.yml"><img src="https://github.com/robot-wranglers/compose.mk/actions/workflows/cmk-demos.yml/badge.svg"></a><a href="https://github.com/robot-wranglers/compose.mk/actions/workflows/compiler-tests.yml"><img src="https://github.com/robot-wranglers/compose.mk/actions/workflows/compiler-tests.yml/badge.svg"></a><a href="https://github.com/robot-wranglers/compose.mk/actions/workflows/docker-publish.yml"><img src="https://github.com/robot-wranglers/compose.mk/actions/workflows/docker-publish.yml/badge.svg"></a><a href="https://github.com/robot-wranglers/compose.mk/actions/workflows/docker-tests.yml"><img src="https://github.com/robot-wranglers/compose.mk/actions/workflows/docker-tests.yml/badge.svg"></a><a href="https://github.com/robot-wranglers/compose.mk/actions/workflows/docs-build.yml"><img src="https://github.com/robot-wranglers/compose.mk/actions/workflows/docs-build.yml/badge.svg"></a><a href="https://github.com/robot-wranglers/compose.mk/actions/workflows/docs.yml"><img src="https://github.com/robot-wranglers/compose.mk/actions/workflows/docs.yml/badge.svg"></a><a href="https://github.com/robot-wranglers/compose.mk/actions/workflows/integration-tests.yml"><img src="https://github.com/robot-wranglers/compose.mk/actions/workflows/integration-tests.yml/badge.svg"></a><a href="https://github.com/robot-wranglers/compose.mk/actions/workflows/notebook-pipeline.yml"><img src="https://github.com/robot-wranglers/compose.mk/actions/workflows/notebook-pipeline.yml/badge.svg"></a><a href="https://github.com/robot-wranglers/compose.mk/actions/workflows/perf-tests.yml"><img src="https://github.com/robot-wranglers/compose.mk/actions/workflows/perf-tests.yml/badge.svg"></a><a href="https://github.com/robot-wranglers/compose.mk/actions/workflows/plugin-tests.yml"><img src="https://github.com/robot-wranglers/compose.mk/actions/workflows/plugin-tests.yml/badge.svg"></a><a href="https://github.com/robot-wranglers/compose.mk/actions/workflows/release-ci.yml"><img src="https://github.com/robot-wranglers/compose.mk/actions/workflows/release-ci.yml/badge.svg"></a><a href="https://github.com/robot-wranglers/compose.mk/actions/workflows/smoke-tests.yml"><img src="https://github.com/robot-wranglers/compose.mk/actions/workflows/smoke-tests.yml/badge.svg"></a><a href="https://github.com/robot-wranglers/compose.mk/actions/workflows/tests.yml"><img src="https://github.com/robot-wranglers/compose.mk/actions/workflows/tests.yml/badge.svg"></a><a href="https://github.com/robot-wranglers/compose.mk/actions/workflows/tui-tests.yml"><img src="https://github.com/robot-wranglers/compose.mk/actions/workflows/tui-tests.yml/badge.svg"></a><a href="https://github.com/robot-wranglers/compose.mk/actions/workflows/unit-tests.yml"><img src="https://github.com/robot-wranglers/compose.mk/actions/workflows/unit-tests.yml/badge.svg"></a>&nbsp; 

Main documentation: [https://robot-wranglers.github.io/compose.mk](https://robot-wranglers.github.io/compose.mk)

<hr style="width:95%;border-bottom:1px dashed black;">

**Meet compose.mk, a tool / library / framework for Makefile-based automation, scripting, and lightweight orchestration.**  Support for docker, docker-compose, workflow primitives, TUI elements, and more, all provided by a single file with no dependencies beyond what's already in your development environment.

Typical use-cases include **general project automation**, especially decoupling your CI/CD from different kinds of platform lock-in.  Other superpowers include the ability to **quickly incorporate foreign tools and foreign code** as first-class objects, which provides unique and powerful capabilities for quickly assembling console applications, systems prototyping, and component-oriented design experiments in general.  Definitely <a href=https://robot-wranglers.github.io/compose.mk/overview/#not-the-makefiles-of-your-ancestors><u><strong>not</strong></u> the Makefiles of your ancestors.

<hr style="width:95%;border-bottom:1px dashed black;">

<img alt=demo src=https://robot-wranglers.github.io/compose.mk/img/docker.commander.gif>

<hr style="width:95%;border-bottom:1px dashed black;">

## Installation

### Fork and Forget

Just drop the single `compose.mk` file into your project and use it directly.  No global install, and no dependencies beyond `make` + `bash` (plus `docker` for the container features).

```bash
# Download into your project and make it executable
$ curl -sL \
    https://raw.githubusercontent.com/Robot-Wranglers/compose.mk/main/compose.mk \
    > compose.mk
$ chmod +x compose.mk
 
# Stand-alone "tool mode"
# Or, from your project Makefile:  `include compose.mk`
$ ./compose.mk <target>     
```

### Global Install

Prefer it **globally, on your `PATH`**?  That's supported with several different installer shims.  Pick your package manager:

| Via | Install |
| --- | --- |
| <a href="https://github.com/robot-wranglers/compose.mk/tree/main/via/basher" style="text-decoration-line:none;">basher</a> | `basher install Robot-Wranglers/compose.mk` |
| <a href="https://github.com/robot-wranglers/compose.mk/tree/main/via/pip" style="text-decoration-line:none;">pip</a> | `pip install "git+https://github.com/Robot-Wranglers/compose.mk.git#subdirectory=via/pip"` |
| <a href="https://github.com/robot-wranglers/compose.mk/tree/main/via/npm" style="text-decoration-line:none;">npm</a> | `npm install -g ./via/npm` *(from a checkout)* |
| <a href="https://github.com/robot-wranglers/compose.mk/tree/main/via/docker" style="text-decoration-line:none;">docker</a> | `docker build -t compose.mk "https://github.com/Robot-Wranglers/compose.mk.git#main:via/docker"` *(runs from a container; or `docker pull ghcr.io/robot-wranglers/compose.mk`)* |

See the [Quickstart](https://robot-wranglers.github.io/compose.mk/quickstart) for tighter project integration and the [compatibility notes](https://robot-wranglers.github.io/compose.mk/quickstart/#compatibility-notes).

