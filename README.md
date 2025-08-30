# action-circuitpython-builder

## Introduction

`action-circuitpython-builder` is a GitHub Action designed to build CircuitPython ports. It supports multiple platforms and targets, enabling developers to quickly build and release CircuitPython projects.

## Features

- Supports multiple CircuitPython platforms (e.g., espressif, nordic).
- Supports build and release targets.
- Allows specifying single or multiple boards for building.

## Usage

### 1. Reference in Workflow

Add the following to your GitHub Actions workflow file:

```yaml
yaml
jobs:
  build:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout repository
        uses: actions/checkout@v3

      - name: Build CircuitPython
        uses: fobe-projects/action-circuitpython-builder@v1
        with:
          port: "nordic"
          target: "build"
          board: "fobe_quill_nrf52840_mesh"
```

### 2. Input Parameters

| Parameter Name  | Required | Default  | Description                                   |
|-----------------|----------|----------|-----------------------------------------------|
| `port`  | Yes      | None     | CircuitPython platform (e.g., espressif, nordic). |
| `target`    | No       | `build`  | Target to run, options are `build` or `release`.   |
| `board`     | No       | None     | board to build (if target is `release`, specify multiple boards). |

### 3. Examples

#### Build a Single Board

```yaml
yaml
jobs:
  build:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout repository
        uses: actions/checkout@v3

      - name: Build CircuitPython for Nordic
        uses: fobe-projects/action-circuitpython-builder@v1
        with:
          port: "nordic"
          target: "build"
          board: "fobe_quill_nrf52840_mesh"
```

#### Release Multiple Boards

```yaml
yaml
jobs:
  release:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout repository
        uses: actions/checkout@v3

      - name: Release CircuitPython for multiple boards
        uses: fobe-projects/action-circuitpython-builder@v1
        with:
          port: "nordic"
          target: "release"
          board: "board1 board2 board3"
```

## License

This project is licensed under the MIT License. For details, see [LICENSE](./LICENSE).
