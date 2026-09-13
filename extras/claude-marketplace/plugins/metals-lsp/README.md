# metals-lsp

Scala language server ([Metals](https://scalameta.org/metals/)) for Claude Code, in the
same shape as the official `*-lsp` plugins.

## Installation

Install Metals with coursier, which puts a `metals` launcher on your PATH:

```sh
cs install metals
```

Metals needs a JDK 17 or newer and a build tool it knows (sbt, Mill, scala-cli, Gradle,
Maven); it imports the build on first start, which can take a few minutes on a large
project, hence the generous startup timeout.

Then add this marketplace and install the plugin:

```sh
claude plugin marketplace add <path to your clone>/extras/claude-marketplace
claude plugin install metals-lsp@factory-extras
```
