
# Alchemix X Aztec - Money Legos Hackathon

This repository is cloned from  [Aztec's official Aztec-Connect repository](https://github.com/AztecProtocol/aztec-connect-bridges). Files that were not needed for the Alchemix Integration has been removed. Files in the folders [bridge/alchemix](https://github.com/tajobin/Alchemix-Aztec-Integration/tree/main/src/bridges/alchemix) and [test/bridge/alchemix](https://github.com/tajobin/Alchemix-Aztec-Integration/tree/main/src/test/bridges/alchemix) have been built for this hackathon the rest is provided by the Aztec team to test bridge contracts. 
    
## Introduction

This is a submission to Alchemix Money Legos Hackathon where an integration of Alchemix and Aztec-connect is achieved. By building an aztec-connect bridge contract for alchemix we can not only provide privacy and gas-savings for alchemix users but also provide new use cases where we take advantage of aztec-connects aggregating capabilities and Alchemix's self-repaying debts. 

### What is Aztec-connect? 

Aztec-conenct is a privacy and DeFi-aggregating layer 2 solution. With Aztec-connect users can shield their assets to provide privacy while still being able to interact with L1 contracts through bridge contracts that aggregate L1 interactions. By aggregating L1 interactions users can reduce their gas savings up to a 100x. 

With Aztec-connect L1 protocols can preserve their Layer 1 liquidity while still providing gas savings to their users.

Read More about Aztec [here](https://docs.aztec.network)

## Alchemist Pools
By building a bridge for Alchemix we aggregate users L1 transactions. The most basic application of this is to simply build pools on top of an alchemist contract. Each pool will have one account on the alchemist contract. A pool would be initialized by an admin at a specific collateralization, users would then enter and receive their respective shares and alToken in accordance with the current collateralization of the pool.

#### Example

An admin initialized a pool with a collateralization ratio of 200%, the admin specifies the alchemist contract and yield token. Users on aztec can now aggregate their interactions with this pool and each receive their respective shares and alUSD. Users shares in the pools are minted as ERC-20 tokens that are sent back to users on Aztec together with their minted alUSD. Users can at any point exit the pool and withdraw their collateral and repay their debt.

The collateralization ratio of the pool will decrease as yield is gained. All users entering into the pool will have to adhere to the current collateralization ratio.

If users wish to take out more debt they can simply swap to another pool that has a suitable collateralization ratio.

### Aggregation pool
The bridge provided [here](https://github.com/tajobin/Alchemix-Aztec-Integration/blob/main/src/bridges/alchemix/AlchemixPool.sol) allows for multiply different types of pools. I have built and tested a pool that supports all yield strategies available on Alchemix. For a pool to deployed an admin (possibly the same admin as the admin in the alchemist) has to call the addPool() function on the bridge with the preferred parameters to configure a pool. The admin also has to whitelist the pool that he has initialized so that it can interact with the alchemist and act as an account.

The two flows supported are as following:
#### Deposit and mint: 
Aztec-connect aggregate users that want to deposit and mint, users will deposit the specified underlying token and will receive and ERC-20 representing their shares (shareToken) and the alToken representing their debt.

#### Repay and withdraw:

Aztec-connect aggregate users that want to repay and withdraw, users deposit an amount of their shareToken. Their debt will be repayed through liquidation and they receive the rest of their collateral back.

#### How to replicate

To run the tests on the aggregation pool do the following:

```
git clone git@github.com:tajobin/Alchemix-Aztec-Integration.git
yarn setup
forge test --fork-url 'https://mainnet.infura.io/v3/9ccb2a35e7f64383ac06acbbe33e1a29' --fork-block-number 15392782 --match-contract AlchemistUnitTest
```

#### Limitations and improvments
##### Improvments to Contract
The contract can be extended to provide more functionality.

It could for example automatically take out a flashloan swap it to the alToken and repay the debt instead of liquidating if that is cheaper.

The contract could allow for automatically rebalancing pools that aims to stay at a specified collateralization ratio.

The current contracts is a base that can be extended with more functionality.

##### Improvments to Testing
More in depth testing could be made by more advanced simulations. We could also add end to end testing with the aztec deployed rollup processor instead of having the test contract act as the rollup processor. Aztec has provided tools to simulate proofs and tests integration with the actual rollup processor.

### Funding pool
To showcase the potential that aztec-connect provides I have also built an additional pool that the admin can deploy and connect to the bridge.

This is a pool that can be used for users to continuously provide funds to a beneficiary. In this pool the yield created is send to a beneficiary. This could be used to create pools that fund a public good or pools that support grants or whatever a community wishes to fund. In the [example](https://github.com/tajobin/Alchemix-Aztec-Integration/blob/main/src/test/bridges/alchemix/AlchemistFundingUnitTest.sol) that is provide the pool funds the official gitcoin matching pool. 

The current contract is provided as an example of what is possible and has not been tested.

The flow of the funding pool is the same as the aggregation pool with the difference that the debt taken out and yield earned is send to the beneficiary. Users can at any point exit and get their collateral back (minus the debt) if they wish to stop funding the beneficiary.

The contract provided has very basic functionality and could be extended to provide more versatility. It could for example give users the ability to fund the beneficiary once and then earn the yield themselves to get their debt back. 

To run the example provided do the following:
```
forge test --fork-url 'https://mainnet.infura.io/v3/9ccb2a35e7f64383ac06acbbe33e1a29' --fork-block-number 15392782 --match-contract AlchemistFundingUnitTest
```

### Ideas for future pools
I would also like to highlight some interesting pools that could be supported by an aztec-bridge.

Yield boosting pools where the yield and/or debt is used to earn yield. This could either be done by doubling down on the functionality provided by alchemix to create leveraged positions or by earning yield elsewhere. The advantage of doing this through an aztec-bridge is that users share the gas costs of expensive L1 interactions. A pool could for example be built that takes out a flashloan to create a leveraged position on alchemix where the debt taken is sold to cover the flashloan. 


