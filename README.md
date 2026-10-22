# tartos

An embedded OS.

## License

tartos is distributed under multiple licenses, per directory:

| Component | Description                                    | License |
| --------- | ---------------------------------------------- | ------- |
| `kernel/` | Kernel sources                                 | GPLv3   |
| `dsl/`    | Python 3 DSL compiling the driver-IPC interface | GPLv3   |
| `lib/`    | Userspace (application-facing) interface library | LGPLv3 |
| `doc/`    | Documentation sources                          | —       |

- Full license texts: [LICENSE-GPLv3](LICENSE-GPLv3), [LICENSE-LGPLv3](LICENSE-LGPLv3).
- Every source file carries an `SPDX-License-Identifier` header matching its
  directory (`GPL-3.0-only` for `kernel/` and `dsl/`, `LGPL-3.0-only` for `lib/`).

## Development

Coding style, comment conventions, directory layout and formatting tooling are
specified in [AGENTS.md](AGENTS.md). Run `./tools/format-all.sh` to format all
sources, or install the git hook once per clone:

```bash
git config core.hooksPath tools/git-hooks
```
