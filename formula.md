# Weighted Average Vesting System - Formula Guide

## Overview
Instead of creating multiple separate vesting positions for the same token, we use a **single consolidated position** with a weighted average end time.

## Core Concept
Every deposit has the same vesting period (1000 days), but can start at different times. We combine them into one position using weighted averages.

---

## Step-by-Step Formulas

### Step 1: First Deposit
When a user makes their **first deposit** of a token:

```
totalAllocated = amount
firstDepositTime = current_time
endTime = current_time + 1000_days
weightedEndTime = amount × endTime
totalClaimed = 0
```

**Example:**
- Deposit 9.78 tokens at timestamp 1758576311
- totalAllocated = 9.78
- firstDepositTime = 1758576311
- endTime = 1758576311 + 86,400,000 = 1844976311
- weightedEndTime = 9.78 × 1844976311 = 18,043,866,321

---

### Step 2: Additional Deposits
When adding more of the **same token**:

```
newEndTime = current_time + 1000_days
weightedEndTime = weightedEndTime + (new_amount × newEndTime)
totalAllocated = totalAllocated + new_amount
```

**Example:**
- Current position: 9.78 tokens, weightedEndTime = 18,043,866,321
- Add 1.17 tokens at timestamp 1758760678
- newEndTime = 1758760678 + 86,400,000 = 1845160678
- weightedEndTime = 18,043,866,321 + (1.17 × 1845160678) = 18,043,866,321 + 2,158,837,993 = 20,202,704,314
- totalAllocated = 9.78 + 1.17 = 10.95

---

### Step 3: Calculate Effective End Time
The **actual vesting end time** for the consolidated position:

```
effectiveEndTime = weightedEndTime ÷ totalAllocated
```

**Example with all 8 deposits:**
- totalAllocated = 57.33 tokens
- weightedEndTime = 105,834,913,874,437 (sum of all weighted times)
- effectiveEndTime = 105,834,913,874,437 ÷ 57.33 = 1,845,161,759 (Day 1002.2 from start)

---

### Step 4: Calculate Total Vesting Duration

```
vestingDuration = effectiveEndTime - firstDepositTime
```

**Example:**
- vestingDuration = 1,845,161,759 - 1,758,576,311 = 86,585,448 seconds (≈1002.2 days)

---

### Step 5: Calculate Vested Amount at Any Time

```
timeElapsed = current_time - firstDepositTime
totalVested = (totalAllocated × timeElapsed) ÷ vestingDuration
```

**Example at Day 100:**
- timeElapsed = 100 × 86,400 = 8,640,000 seconds
- totalVested = (57.33 × 8,640,000) ÷ 86,585,448 = 5.72 tokens

---

### Step 6: Calculate Pending (Claimable) Amount

```
pending = totalVested - totalClaimed
```

**Example at Day 100 (no previous claims):**
- totalVested = 5.72 tokens
- totalClaimed = 0
- pending = 5.72 - 0 = 5.72 tokens

**Example at Day 500 (claimed 11.44 tokens on Day 200):**
- totalVested = (57.33 × 43,200,000) ÷ 86,585,448 = 28.60 tokens
- totalClaimed = 11.44 tokens
- pending = 28.60 - 11.44 = 17.16 tokens

---

### Step 7: Daily Vesting Rate

```
dailyRate = totalAllocated ÷ (vestingDuration_in_days)
```

**Example:**
- dailyRate = 57.33 ÷ 1002.2 = 0.0572 tokens per day

---

## Complete Example with Real Data

**Your 8 deposits:**
1. 9.78 tokens at time 1758576311
2. 1.17 tokens at time 1758760678  
3. 17.26 tokens at time 1758760727
4. 4.51 tokens at time 1758763388
5. 3.36 tokens at time 1758763726
6. 8.85 tokens at time 1758812468
7. 3.41 tokens at time 1759079696
8. 8.99 tokens at time 1759079789

**Final consolidated position:**
```
totalAllocated = 57.33 tokens
firstDepositTime = 1758576311
weightedEndTime = 105,834,913,874,437
effectiveEndTime = 1,845,161,759
vestingDuration = 86,585,448 seconds (1002.2 days)
dailyRate = 0.0572 tokens/day
```

---

## Key Benefits

1. **Single Position**: Instead of 8 separate vestings, you have 1 consolidated position
2. **Constant Rate**: 0.0572 tokens vest per day (predictable)
3. **Gas Efficient**: One calculation instead of 8
4. **Fair**: Weighted by amount, so larger deposits have more influence on end time

---

## Edge Cases

### When to Auto-Claim Before New Deposit
Before adding to an existing position, calculate and claim pending tokens:

```
if (existing_position_exists) {
    pending = calculate_pending()
    if (pending > 0) {
        claim(pending)
        totalClaimed = totalClaimed + pending
    }
}
```

This prevents users from losing vested tokens when the weighted average shifts.

### Maximum Extension from First Deposit
With weighted average, the maximum extension is minimal:

```
maxExtension = (lastDepositTime - firstDepositTime)
```

In your example: 6 days of deposits → ~2 day extension (0.2% of 1000 days)

---

## Summary

The weighted average method consolidates multiple token deposits into a single vesting position with:
- **One effective end time** (weighted average of all deposits)
- **Constant daily vesting rate** 
- **Simple pending calculation** (vested - claimed)
- **Fair distribution** based on deposit amounts
- **Gas efficient** single position management
