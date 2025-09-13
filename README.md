# 🪙 Presale

Presale is a complete mini-protocol for managing the launch of a new ERC20 token, FlyToken. It allows users to buy tokens before they are listed on a DEX, across 3 phases with different prices and time limits, fee and blacklist mechanisms, with secure ETH/USD price conversion via Chainlink. It integrates several smart contracts (Presale, FlyToken, MockAggregator, MockTreasury) working together, everything fully covered by unit, fuzzing, invariant, and mainnet-fork tests on Arbitrum One.

## ✨ Features

- 🪙 **New ERC20 Token**: FlyToken is minted and allocated for sale during the presale.
- 🪙 **Buy with Stablecoins**: purchase FlyToken using USDT or USDC.
- ⚡ **Buy with ETH**: ETH payments are automatically converted to USD using Chainlink oracles.
- 🔗 **Chainlink oracle**: data feed USDT/ETH price.
- 📈 **Phased Presale**: configurable supply, price, and duration for each phase.
- 🚫 **Blacklist Mechanism**: owner can restrict malicious addresses.
- 🛡️ **Claim Period**: users claim tokens after the presale ends.
- 💸 **Fee System**: protocol collects fees in both ERC20 and ETH.
- 🔓 **Fee Withdrawal**: only the owner can withdraw accumulated fees (ERC20 or ETH) after the presale ends.
- 🆘 **Emergency Withdraw**: owner can rescue tokens or ETH if needed.

## 📊 Flow Diagram

```mermaid
flowchart TD

    subgraph Presale
        B1[buyWithTokens()]
        B2[buyWithETH()]
        C1[claimTokens()]
        W1[withdrawFees()]
        E1[emergencyWithdrawTokens()]
        E2[emergencyWithdrawETH()]
        BL[blacklist/unBlacklist()]
    end

    subgraph FlyToken
        FT1[_mint()]
        FT2[approve()]
        FT3[transfer()]
    end

    subgraph MockAggregator
        MA1[latestRoundData()]
    end

    subgraph MockTreasury
        MT1[receive ETH]
        MT2[receive USDT/USDC]
    end

    %% Relationships
    B1 -->|uses USDT/USDC| MockTreasury
    B2 -->|uses ETH/USD price| MockAggregator
    B2 -->|sends ETH| MockTreasury
    C1 -->|sends FlyToken| FlyToken
    W1 -->|sends fees| Owner
    E1 -->|withdraw tokens| Owner
    E2 -->|withdraw ETH| Owner

    Presale --> FlyToken

```

## 🔐 Security Measures and Patterns

- 🪙 **SafeERC20**: all token transfers use `SafeERC20` to handle non-standard ERC20 implementations safely
- 🔑 **Access Control**: `onlyOwner` modifier restricts privileged functions (`blacklist`, `withdrawFees`, `emergencyWithdraw`, etc.)
- 🛡️ **Reentrancy Protection**: critical functions (`buyWithTokens`, `buyWithETH`, `claimTokens`, `withdrawFees`) are protected with OpenZeppelin’s `ReentrancyGuard`
- 📢 **Event Logging**: all state mutations emit events (`TokensBought`, `ETHBought`, `TokensClaimed`, `FeeWithdrawn`, etc.) for transparency and off-chain monitoring
- 🧩 **CEI Pattern**: all external functions follow the Checks-Effects-Interactions pattern to minimize vulnerabilities
- 🔗 **Chainlink Oracle**: secure ETH/USD price feed integration prevents manipulation of ETH payments
- 🧪 **Testing**: complete unit tests, fuzzing test, and mocks ensure robustness
- 🔄 **Forked Mainnet Testing**: validated on Arbitrum One with real USDT, USDC, and Chainlink feeds

## 🧪 Tests

Complete suite test using **Foundry**, with forked Arbitrum RPC for integration and  
two mock contracts (`MockAggregator.sol` for the Chainlink price feed and `MockTreasury.sol` for ETH/stablecoin receiving).

The suite includes happy paths, negative paths, edge cases, fuzzing, and invariant tests to ensure robustness.

- ✅ `buyWithTokens()` – happy path, invalid token, zero amount, blacklist, presale inactive, max supply, phase changes
- ✅ `buyWithETH()` – happy path, zero amount, blacklist, presale inactive, oracle integration, max supply
- ✅ `claimTokens()` – happy path, before claim period, nothing to claim, double claim
- ✅ `blacklist()` / `unBlacklist()` – owner only, reverts for non-owners
- ✅ `withdrawFees()` – ERC20 and ETH fees, reverts if not owner or before claim period
- ✅ `emergencyWithdrawTokens()` – owner only, reverts for non-owners
- ✅ `emergencyWithdrawETH()` – owner only, reverts for non-owners
- ✅ Fuzzing tests for token and ETH purchases
- ✅ Invariant tests for max supply and fee consistency

Run tests with:

```bash
forge test --fork-url https://arb1.arbitrum.io/rpc --vvvv --match-test test_buyWithTokens
```

## 🧠 Technologies Used

- ⚙️ **Solidity** (`^0.8.24`) – smart contract programming language
- 🧪 **Foundry** – framework for development, testing, fuzzing, invariants and deployment
- 📚 **OpenZeppelin Contracts** – `ERC20`, `Ownable`, `ReentrancyGuard`, `SafeERC20`
- 🔗 **Chainlink Oracles** – secure ETH/USD price feed integration
- 🌐 **Arbitrum One** – mainnet fork for realistic testing with live USDT, USDC and Chainlink feeds
- 🛠️ **Mocks** – custom `MockAggregator` and `MockTreasury` contracts for local testing

## 📜 License

This project is licensed under the MIT License.
