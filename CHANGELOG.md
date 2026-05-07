## [0.7.0](https://github.com/egose/actions/compare/v0.6.0...v0.7.0) (2026-05-07)

### Features

* add ignore-scripts support to npm-packages ([6132626](https://github.com/egose/actions/commit/6132626ac848ce541cef209eee86a3a13bb78c40))
* add ignore-scripts support to pnpm-packages ([d602d63](https://github.com/egose/actions/commit/d602d639695a124e497746294c013346c3de97fd))
* add ignore-scripts support to yarn-packages ([217ded8](https://github.com/egose/actions/commit/217ded8ae8aa7be0f543653afa80c25baafc2651))

## [0.6.0](https://github.com/egose/actions/compare/v0.5.2...v0.6.0) (2026-05-04)

### Features

* add frozen lockfile support to yarn-packages ([2fc9f81](https://github.com/egose/actions/commit/2fc9f81c341c7a2d7584c3cfa1e6f5fd72f65e19))
* add npm-packages action ([4721f7a](https://github.com/egose/actions/commit/4721f7ac56f0cd357abf65ea6cddc1557e250b9e))
* add pnpm-packages action ([365f01b](https://github.com/egose/actions/commit/365f01bf8fae5a561a95f62500bc5c58198700a6))

### Docs

* register npm and pnpm actions in root README ([57148bd](https://github.com/egose/actions/commit/57148bd3c7cfc69fd39ddac74fd39bf52b836420))

## [0.5.2](https://github.com/egose/actions/compare/v0.5.1...v0.5.2) (2026-05-04)

## [0.5.1](https://github.com/egose/actions/compare/v0.5.0...v0.5.1) (2026-05-04)

## [0.5.0](https://github.com/egose/actions/compare/v0.4.0...v0.5.0) (2026-05-04)

### Features

* add GPG signing support for release commits ([72b4474](https://github.com/egose/actions/commit/72b4474f6e8068d0db3492528c3e420fd43e52fc))

## [0.4.0](https://github.com/egose/actions/compare/v0.3.0...v0.4.0) (2026-05-03)

### Features

* add auto-merge and branch deletion to release-tag ([6ff3d4a](https://github.com/egose/actions/commit/6ff3d4ac41daa03edd75823f353e30c3ab670cb9))
* add composite actions for setup and tools ([b64bb22](https://github.com/egose/actions/commit/b64bb22219a4c92f2108a107256bcbf30b1572f7))
* add precommit package ([9d4105c](https://github.com/egose/actions/commit/9d4105c6e9a42f498633f51e73c1c3f736815195))
* add release automation and commit linting ([65d1fe7](https://github.com/egose/actions/commit/65d1fe7b460b2a38a31fb1ed7f6a0b31cbebf22b))
* add release tag action ([e1d8d82](https://github.com/egose/actions/commit/e1d8d82f674a51abe3850a89349c231dd7513a68))
* add trivy scanner option ([e54f6eb](https://github.com/egose/actions/commit/e54f6ebda1e60a2e68af31f57c9bae5e06cb28e1))
* **asdf-tools:** install asdf from release assets ([d5ffec3](https://github.com/egose/actions/commit/d5ffec39a2062fbc8f59c8106c378f5561af2e98))
* **asdf-tools:** upgrade adsf version ([df28849](https://github.com/egose/actions/commit/df28849473f80167618be433459696793910c393))
* **docker-build-push:** add step summary after trivy results ([c2f58cb](https://github.com/egose/actions/commit/c2f58cbd9a4423fba66c4ab841b1539e4e9c66ac))
* **docker-build-push:** declare outputs ([97fff4a](https://github.com/egose/actions/commit/97fff4a960b7f2db201eed7012958e4e2f9439f3))
* **docker-build-push:** set default arg BUILD_TIMESTAMP ([9b728b5](https://github.com/egose/actions/commit/9b728b5e6d2f62ea88895c1822cd30b58bd1fecb))
* enhance precommit action with verification and error tracking ([961cf13](https://github.com/egose/actions/commit/961cf1393ab4ff42f550f6379212267c4cc4ca43))
* **release-tag:** add new input release-it-path ([5dfa6fc](https://github.com/egose/actions/commit/5dfa6fc0c0153a43fb5a127047e724dee0f2ed07))
* update precommit package ([0845fa6](https://github.com/egose/actions/commit/0845fa6ad2ffe7b3315556c0fec2b2498366dc79))

### Bug Fixes

* correct metadata output keys ([507daea](https://github.com/egose/actions/commit/507daeabb7bc433fc81bc5aa93718f6dc12173c5))
* correct variable name and indentation in yarn-packages ([76fff19](https://github.com/egose/actions/commit/76fff19d4bc2e3071f16ecc5eb9e0ef517dd34a7))
* improve quoting and error handling in asdf-tools ([8672290](https://github.com/egose/actions/commit/8672290b0351fddb30dc110d6072e4890bc18b8b))
* push branch after release-it execution in release-tag ([8257dfc](https://github.com/egose/actions/commit/8257dfce3dc7e38750ca132a8e19168e02f01240))
* resolve issue with sh ([3c35039](https://github.com/egose/actions/commit/3c3503972ec1d1e9562a0c44b2417b4409c59d91))
* use 127.0.0.1 for local registry in docker tests ([8d9efe4](https://github.com/egose/actions/commit/8d9efe4582c41ad02f33d5329b6b2e0e35bc680b))

### Docs

* overhaul module documentation and root index ([02c6db1](https://github.com/egose/actions/commit/02c6db1d87c34a809953b36291a4ffce37ca803c))
* update license to Apache-2.0 ([35eba1a](https://github.com/egose/actions/commit/35eba1a3e33d0eb37396ed33476490ccd3e058c2))

### Refactors

* delegate root action to docker-build-push ([d70c38b](https://github.com/egose/actions/commit/d70c38b711ea6610449231662a39663b0ff6c285))

## [0.2.2](https://github.com/egose/actions/compare/v0.2.1...v0.2.2) (2023-06-08)

## [0.2.1](https://github.com/egose/actions/compare/v0.2.0...v0.2.1) (2023-06-08)

## [0.2.0](https://github.com/egose/actions/compare/v0.1.0...v0.2.0) (2023-03-10)

### Features

* add asdf-tools and yarn-packages ([7a73463](https://github.com/egose/actions/commit/7a73463189243f7f690d4e6703c4096f5ef32e2a))

## [0.1.0](https://github.com/egose/actions/compare/df5a69a2112b94b2f76fa6df42373260542b1fde...v0.1.0) (2023-03-08)

### Features

* add initial action ([df5a69a](https://github.com/egose/actions/commit/df5a69a2112b94b2f76fa6df42373260542b1fde))
