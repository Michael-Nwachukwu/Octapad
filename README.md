# OctaPad x Octant YieldDonating Strategy

> **Regenerative Token Launchpad** - Where platform fees earn yield for public goods

[![Tests](https://img.shields.io/badge/tests-6%2F6%20passing-brightgreen)]()
[![Network](https://img.shields.io/badge/network-Base-blue)]()
[![Solidity](https://img.shields.io/badge/solidity-0.8.25-orange)]()

---

## 🎯 What It Is

**OctaPad** is a token launchpad integrated with **Octant's YieldDonating Strategy** to create a **regenerative funding model** where platform fees automatically generate yield for public goods. Every campaign launched on OctaPad contributes capital to a yield-generating strategy, creating a sustainable revenue stream that benefits both the ecosystem and campaign participants.

### Key Innovation
Instead of keeping fees idle or immediately spending them, **all platform revenue flows into a yield-generating strategy** that:
- Earns continuous yield from Kalani vault on Base
- Distributes 50% of profits to public goods (via Dragon Router)
- Distributes 50% of profits to campaign participants (OG Points holders)

---

## 🔄 The Regenerative Flywheel

```
┌─────────────────────────────────────────────────────────────────┐
│                    THE REGENERATIVE FLYWHEEL                     │
│                                                                   │
│  ┌──────────────┐                                                │
│  │   Creators   │                                                │
│  │ Launch Token │                                                │
│  │  Campaigns   │                                                │
│  └──────┬───────┘                                                │
│         │                                                         │
│         │ Sponsorship (100 USDC)                                │
│         │ Platform Fee (5%)                                      │
│         │ Vested Funds (20%)                                     │
│         │ Trading Fees (50% of swaps)                           │
│         ▼                                                         │
│  ┌─────────────────────────────┐                                │
│  │   YieldDonating Strategy    │                                │
│  │  ┌────────────────────────┐ │                                │
│  │  │   Kalani Vault (Base)  │ │◄─── Deposits USDC             │
│  │  │                        │ │                                │
│  │  │  Earns Yield (APY%)    │ │──► Generates Profit            │
│  │  └────────────────────────┘ │                                │
│  │                              │                                │
│  │  Profit = 100% minted as    │                                │
│  │  shares to PaymentSplitter  │                                │
│  └──────────────┬───────────────┘                                │
│                 │                                                 │
│                 │ Profit Shares                                  │
│                 ▼                                                 │
│  ┌──────────────────────────────────────┐                       │
│  │      PaymentSplitter (50/50)         │                       │
│  ├──────────────────┬───────────────────┤                       │
│  │  50% shares      │    50% shares     │                       │
│  ▼                  ▼                    │                       │
│ ┌──────────────┐  ┌─────────────────┐  │                       │
│ │Dragon Router │  │ OG Points Holders│  │                       │
│ │(Public Goods)│  │   (Participants) │  │                       │
│ └──────┬───────┘  └────────┬─────────┘  │                       │
│        │                   │             │                       │
│        │                   │ Redeem      │                       │
│        │                   │ for USDC    │                       │
│        │                   ▼             │                       │
│        │          ┌─────────────────┐   │                       │
│        │          │ Higher Rewards  │   │                       │
│        │          │ = More Campaigns│───┤────────┐              │
│        │          └─────────────────┘   │        │              │
│        │                                │        │              │
│        │  Funds Public                  │        │              │
│        │  Good Projects                 │        │              │
│        ▼                                │        │              │
│   ┌──────────────────┐                  │        │              │
│   │ Ecosystem Growth │                  │        │              │
│   │  More Users &    │                  │        │              │
│   │ More Campaigns   │──────────────────┘        │              │
│   └──────────────────┘                           │              │
│             │                                     │              │
│             └─────────────────────────────────────┘              │
│                   FLYWHEEL ACCELERATES                           │
└─────────────────────────────────────────────────────────────────┘

KEY INSIGHT: More campaigns → More capital → More yield → Better rewards
→ More campaigns... The flywheel keeps spinning!
```

---

## 🚀 Quick Start

```bash
# Clone and install
git clone <repo-url>
cd octant-v2-strategy-foundry-mix
forge install

# Run all tests
forge test
```

---

## 💡 Key Innovation: Vesting Capital Efficiency

**Traditional Vesting:**
```
Campaign completes → 20% locked in vesting → Sits idle for 90 days → $0 yield
```

**Our Innovation:**
```
Campaign completes → 20% deposited to Strategy → Earns 15% APY → ~$75 profit
                                                   ↓
                                   Creator still gets vesting protection!
```

**Example:** $2,000 vested over 90 days
- Traditional: $0 yield
- Our approach: ~$75 profit for ecosystem (at 15% APY)
- Creator: Still receives full $2,000 after vesting period

**Win-Win-Win:** Capital works during vesting, ecosystem earns yield, creator gets safety

---

## 📊 Economic Model

### Example: 10 Campaigns × $10,000 Each = $100,000 Raised

```
CAPITAL TO STRATEGY:
├─ Sponsorship (10 × $100):        $1,000
├─ Platform Fees (10 × 5%):        $5,000
├─ Vested Funds (10 × 20%):       $20,000
└─ TOTAL:                         $26,000 earning yield

ANNUAL YIELD (15% APY):
└─ Profit:                         $3,900

PROFIT DISTRIBUTION (50/50):
├─ Dragon Router:                  $1,950 → Public goods
└─ OG Points Holders:              $1,950 → Participants

PLUS: Ongoing trading fees from 10 Uniswap pools!
```

### Network Effects

| Campaigns | Strategy TVL | Annual Yield (15%) | Public Goods | Participants |
|-----------|--------------|-------------------|--------------|--------------|
| 10 | $26k | $3,900 | $1,950 | $1,950 |
| 100 | $260k | $39,000 | $19,500 | $19,500 |
| 1,000 | $2.6M | $390,000 | $195,000 | $195,000 |

**The flywheel accelerates as the platform grows!**

---

## 🏗️ Architecture Overview

```
┌────────────────────── OCTAPAD LAUNCHPAD ──────────────────────┐
│                                                                 │
│  Campaign Creation → Token Sales → Bonding Curve Pricing       │
│                                                                 │
│  ALL FEES FLOW DOWN ↓                                          │
│                                                                 │
└────────────────────────────────────────────────────────────────┘
                               │
                               ↓
┌────────────── YIELDDONATING STRATEGY (Octant v2) ─────────────┐
│                                                                 │
│  ┌────────────────────────────────────────────────────┐       │
│  │  Kalani Vault (Base)                               │       │
│  │  • USDC deposit                                    │       │
│  │  • 5-15% APY                                       │       │
│  │  • ERC4626 standard                                │       │
│  └────────────────────────────────────────────────────┘       │
│                                                                 │
│  Profit shares (100%) ↓                                        │
│                                                                 │
└────────────────────────────────────────────────────────────────┘
                               │
                               ↓
┌───────────────── PAYMENTSPLITTER (50/50) ────────────────────┐
│                                                                │
│  ┌────────��────────────┐       ┌────────────────────────┐    │
│  │  Dragon Router      │       │  OG Points Holders     │    │
│  │  (Public Goods)     │       │  (Participants)        │    │
│  │  • 50% of profits   │       │  • 50% of profits      │    │
│  │  • Funds ecosystem  │       │  • Proportional        │    │
│  └─────────────────────┘       └────────────────────────┘    │
│                                                                │
└────────────────────────────────────────────────────────────────┘
```

---

## 🎯 Benefits

### For Campaign Creators
- ✅ Only 100 USDC sponsorship (vs 10k+ traditional)
- ✅ Automatic Uniswap v4 liquidity
- ✅ Fair bonding curve pricing
- ✅ Vesting funds earn yield in background

### For Token Buyers
- ✅ Fair transparent pricing
- ✅ Instant trading on Uniswap v4
- ✅ Earn OG Points for participation
- ✅ Receive proportional yield rewards

### For Public Goods
- ✅ Continuous yield stream
- ✅ Scales with platform growth
- ✅ Transparent on-chain distribution
- ✅ Sustainable funding model

### For Octant Ecosystem
- ✅ New revenue stream
- ✅ Demonstrates v2 strategy flexibility
- ✅ Base network integration
- ✅ Regenerative economic model

---

## 🔐 Security

- ✅ All critical functions have reentrancy protection
- ✅ SafeERC20 for all token transfers
- ✅ Role-based access control
- ✅ Circuit breaker for vault failures
- ✅ Emergency withdrawal capabilities
- ✅ 6/6 integration tests passing

---

## 📝 Contract Addresses (Base)

### Core Dependencies
- **USDC**: `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913`
- **Kalani Vault**: `0x7ea9FAC329636f532aE29E1c9EC9A964337bDA24`

### OctaPad Contracts (To be deployed)
- **YieldDonatingStrategy**: 0xD148CbC97d825dbEBe2bF03DfbE634972CE1F4dc
- **OctaPad**: 0x583518a01856027EF42C55f4762F156971f6A0c8
- **OGPointsToken**: 0x4d0884D03f2fA409370D0F97c6AbC4dA4A8F03d6
- **OGPointsRewards**: 0x9f3eB17a20a4E57Ed126F34061b0E40dF3a4f5C2
- **VestingManager**: 0xfe7da8f89dc0acf86406457d8ed5637c71e1fb25
- **PaymentSplitter**: 0xb3A08f77D37904d42BD5599daCcDD405a42C6A1E (proxy)
- **OctaPadDEX**: 0x9d6e23b6B029BEaC49C43679304D32fDBf88F42A

---

## 📚 Key Files

### Core Contracts
- `src/strategies/YieldDonating/YieldDonatingStrategy.sol` - Strategy Implementation
- `src/launchpad/OctaPad.sol` - Core launchpad (deposits fees to strategy)
- `src/launchpad/VestingManager.sol` - Immediate strategy deposits
- `src/launchpad/OGPointsRewards.sol` - Proportional yield distribution
- `src/hooks/YieldDonatingFeeHook.sol` - Captures 50% of swap fees

### Tests
- `test/` - 6 integration tests files (all passing ✅)
- `src/strategies/test/yieldDonating` - 4 Fork tests files (all passing ✅)

---

## 🙏 Acknowledgments

- **Octant Team**: YieldDonating Strategy and PaymentSplitter
- **Kalani Finance**: Yield vault on Base
- **Uniswap Labs**: v4 and hooks
- **Base Network**: L2 infrastructure
- **OpenZeppelin**: Smart contract library

---

<div align="center">

**Built with ❤️ for sustainable public goods funding**

*"Every campaign launched makes the ecosystem stronger"*

---

**Project Status:** ✅ All core features implemented | ✅ Integration tests passing | ✅ Deployed on base mainnet

</div>
