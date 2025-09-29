# Bitswap Vesting Contract

A smart contract system for token vesting using a weighted average consolidation approach.

## 📄 Contract Files

- **vestingvault.sol** - Main vesting vault contract
- **abi.json** - Contract ABI
- **formula.md** - Detailed explanation of the weighted average vesting formula

## 🧮 Interactive Calculator

Visit the **[Vesting Calculator](https://yourusername.github.io/bitswap-contract/)** to see the weighted average vesting system in action!

The calculator allows you to:
- Add multiple token deposits at different times
- See real-time weighted average calculations
- Simulate vesting over time
- Test claiming mechanics
- Compare gas costs

## 🚀 Vesting System Overview

### Key Features

- **Single Position Per Token**: Instead of creating multiple vesting entries, deposits are consolidated into one position
- **Weighted Average End Time**: Uses amount-weighted averaging to calculate a fair end time
- **Constant Vesting Rate**: Linear vesting provides predictable daily unlock rates
- **Gas Efficient**: Single position management significantly reduces gas costs

### How It Works

Each deposit vests over exactly **1000 days**. When multiple deposits of the same token are made:

1. Calculate weighted end time: `Σ(amount × endTime) / totalAmount`
2. Consolidate into single position
3. Vest linearly: `vested = (totalAmount × timeElapsed) / vestingDuration`
4. Claim anytime: `pending = vested - claimed`

See [formula.md](formula.md) for detailed mathematical explanation.

## 📊 Example

With 8 deposits totaling 57.33 tokens over 6 days:
- **Effective End Time**: Day 1002 (weighted average)
- **Daily Rate**: 0.0572 tokens/day
- **Gas Savings**: 8x reduction (single vs multiple positions)

## 🛠️ Development

```bash
# Clone repository
git clone https://github.com/yourusername/bitswap-contract.git

# View calculator locally
open index.html
```

## 📝 License

[Your License Here]

## 👥 Contributors

- [Your Name/Team]

---

Built with ❤️ for fair and efficient token vesting
