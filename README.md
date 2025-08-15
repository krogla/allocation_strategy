# Target Share Allocation Strategy

This repository contains a smart contract library designed to implement allocation strategies for Lido ValMart. The main focus is on optimizing validator selection through reputation-weighted calculations and efficient resource distribution using the simplified WaterFilling algorithm.

The library is optimized for gas consumption and supports up to 16 different metrics (parameters) that determine the final weight of each entity and its share in the overall distribution. Each read or update operation has O(1) complexity, allowing efficient data retrieval and updates for specific entities. The test suite includes successful validation with 1000 concurrent entities.

The library is built with Foundry and includes comprehensive tests and documentation to ensure reliability and ease of use.

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test test/ASMockValMart.t.sol -vvv --gas-report
```
