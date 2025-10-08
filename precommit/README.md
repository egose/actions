## About

GitHub Action to install asdf tools.

## Usage

### Basic

By default, it uses `.tool-versions` file located in the root directory to install asdf plugins.

```yaml
name: Basic

on: push

jobs:
  tools:
    runs-on: ubuntu-22.04
    steps:
      - uses: actions/checkout@v3
      - name: Setup Tools
        uses: egose/actions/asdf-tools@v0.2.9
```

### Custom Context Input

You have the option to specify the location of the `.tool-versions` file using the `context` input.

```yaml
name: Custom Context Input

on: push

jobs:
  tools:
    runs-on: ubuntu-22.04
    steps:
      - uses: actions/checkout@v3
      - name: Setup Tools
        uses: egose/actions/asdf-tools@v0.2.9
        with:
          context: ./app
```

### Custom Context Input with Additional Plugins

You can also specify the additional plugins using the `plugins` input.

```yaml
name: Custom Context Input with Additional Plugins

on: push

jobs:
  tools:
    runs-on: ubuntu-22.04
    steps:
      - uses: actions/checkout@v3
      - name: Setup Tools
        uses: egose/actions/asdf-tools@v0.2.9
        with:
          plugins: |
            docker-compose=https://github.com/virtualstaticvoid/asdf-docker-compose.git
```

## Inputs

The following inputs can be used as `step.with` keys:

| Name      | Type   | Required | Default | Description                                       |
| --------- | ------ | -------- | ------- | ------------------------------------------------- |
| `plugins` | String | No       |         | List of additional plugins (e.g., <plugin>=<url>) |
| `context` | String | No       | .       | Directory of the file .tool-versions located      |
