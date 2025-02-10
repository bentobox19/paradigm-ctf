## Paradigm

Solutions to Challenges from Paradigm CTF.

## Scope

* [2023 - Black Sheep](https://github.com/paradigmxyz/paradigm-ctf-2023/tree/main/black-sheep/challenge/project)
* [2023 - Dai Plus Plus](https://github.com/paradigmxyz/paradigm-ctf-2023/tree/main/dai-plus-plus/challenge/project)

## Writeups

* In code, at each test file.

## How to Run

### Install forge

* Follow the [instructions](https://book.getfoundry.sh/getting-started/installation.html) to install [Foundry](https://github.com/foundry-rs/foundry).

### Install dependencies

```bash
forge install
```

### Run the entire test suit

```bash
forge test
```

### Running a single challenge

```bash
forge test --match-contract BlackSheep
```

#### Add traces

There are different level of verbosities, `-vvvvv` is the maximum.

```bash
forge test --match-contract BlackSheep -vvvvv
```
