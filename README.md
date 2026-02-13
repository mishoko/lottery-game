# Lottery.sol - Practice Project

A simple on-chain lottery game built with Solidity for learning and practice.

## What is this?

This is a **fun little project** to practice Solidity development! It's a number-guessing lottery where players bet 1 DAI and try to guess a number closest to the winning number.

## How it works

1. **Place a bet** - Pick a number (1-100) and stake 1 DAI
2. **Wait for reveal** - After 100 blocks, the owner reveals the winning number
3. **Claim your prize** - If your number is closest to the winning number, claim your share of the pot!

## Requirements

- Solidity ^0.8.30
- Foundry (for building and testing)
- DAI token (ERC20)

## Constraints

- **Number range**: 1-100
- **Bet amount**: 1 DAI fixed
- **Game duration**: 100 blocks
- **Winners**: Players with numbers closest to the winning number share the pot equally
- **One bet per address**
- **Owner is trusted**

## Important Disclaimer

**This is a practice project**

- Not production-ready. No intent to be deployed.
- Created for educational purposes only

## Building

```bash
forge build
```

