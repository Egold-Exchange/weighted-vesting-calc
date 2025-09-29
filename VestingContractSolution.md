# Fixing vesting contract token management
_Exported on 9/29/2025 at 15:18:06 GMT+4 from Cursor (1.4.2)_

---

**User**

I have a vesting contract @vestingvault.sol,@abi.json . My goal is to have a logic/system where user can lock different tokens for an amout of time and it will unlock little by little over time. But I'm running into a problem with my current implementation. For the same token I'm ending up creating multiple vestings. this is not what i want. A single vest can have multiple tokens vested in it, but only one position of a single token. But rn for example this is my vesting. i locked same token with multiple transactions over time. the getAllVestings function returns - [[0xd96Af99Bbc1DF687ff207657cc8160383b766006,18,9783340594922168970,1758576311,1844976311,0]
[0xd96Af99Bbc1DF687ff207657cc8160383b766006,18,1170466435490100829,1758760678,1845160678,0]
[0xd96Af99Bbc1DF687ff207657cc8160383b766006,18,17259864931014413302,1758760727,1845160727,0]
[0xd96Af99Bbc1DF687ff207657cc8160383b766006,18,4510521077528646113,1758763388,1845163388,0]
[0xd96Af99Bbc1DF687ff207657cc8160383b766006,18,3358027385578713878,1758763726,1845163726,0]
[0xd96Af99Bbc1DF687ff207657cc8160383b766006,18,8852177377487451588,1758812468,1845212468,0]
[0xd96Af99Bbc1DF687ff207657cc8160383b766006,18,3411943017505651961,1759079696,1845479696,0]
[0xd96Af99Bbc1DF687ff207657cc8160383b766006,18,8993480745416668403,1759079789,1845479789,0]]. This is of the format [token,tokenDecimals,totalAllocated,startTime,endTime,totalClaimed]. Here I only tested with one token which was 0xd96Af99Bbc1DF687ff207657cc8160383b766006. My main problem is how I would implement the endtime, since user can lock at different times but I'm only creating a single position. I can think of something like an endtime using a weighted average based on position. the thing is all vestings will have EXACT same vesting period of 1000 days. We also need to consider that. And each lock can happen on separate days. See the existing example I shared. each vesting is different amount with different start and end time. give me different solutions and how to fix this issue. 

---

**Cursor**

Looking at your vesting contract, I can see the issue - you're creating multiple separate vesting entries for the same token when you want a single consolidated position per token. This is a common challenge with vesting contracts that need to handle multiple deposits over time.

Let me analyze the problem and provide you with several solutions:

## Current Issue Analysis

Your current implementation creates a new vesting entry every time `vestToken` is called, even for the same token. Each entry has its own:
- `startTime` (when that specific deposit was made)
- `endTime` (startTime + 1000 days)
- `totalAllocated` (amount for that specific deposit)

## Solution Options

### **Solution 1: Weighted Average End Time (Recommended)**

This approach maintains a single position per token and calculates a weighted average end time based on the amounts and timing of deposits.

```solidity:vestingvault.sol
// ... existing code ...

contract VestingVault is Initializable, Context, IVestingVault {
    // Modified structure - single vesting per token
    mapping(address => Vest) private tokenVestings;
    
    // Track which tokens have vestings
    address[] public vestedTokens;
    mapping(address => bool) public hasVesting;
    
    // Modified vest structure to handle accumulation
    struct Vest {
        address token;
        uint8 tokenDecimals;
        uint256 totalAllocated;
        uint256 weightedEndTime; // Sum of (amount * endTime) for weighted average
        uint256 totalClaimed;
        uint256 lastDepositTime; // Track most recent deposit
    }
    
    function vestToken(address token, uint256 amount) external override onlyValidPair {
        if(amount == 0) revert InvalidAmount();
        
        uint256 _currentBalance = IERC20(token).balanceOf(address(this));
        if(_currentBalance < lastRecordedTokenBalance[token] + amount) revert InsufficientTokenReceived();
        
        uint256 vestingPeriod = vestingVaultFactory.lockingPeriod();
        uint256 newEndTime = block.timestamp + vestingPeriod;
        
        if (!hasVesting[token]) {
            // First deposit for this token
            tokenVestings[token] = Vest({
                token: token,
                tokenDecimals: IERC20Metadata(token).decimals(),
                totalAllocated: amount,
                weightedEndTime: amount * newEndTime,
                totalClaimed: 0,
                lastDepositTime: block.timestamp
            });
            
            vestedTokens.push(token);
            hasVesting[token] = true;
        } else {
            // Additional deposit for existing token
            Vest storage vest = tokenVestings[token];
            
            // Calculate claimable amount before updating to avoid losing vested tokens
            uint256 currentlyClaimable = _calculateClaimable(token);
            if (currentlyClaimable > 0) {
                // Auto-claim before adding new deposit to preserve vested rights
                _autoClaimBeforeDeposit(token, currentlyClaimable);
            }
            
            // Update weighted average end time
            uint256 newTotalAllocated = vest.totalAllocated + amount;
            vest.weightedEndTime = vest.weightedEndTime + (amount * newEndTime);
            vest.totalAllocated = newTotalAllocated;
            vest.lastDepositTime = block.timestamp;
        }
        
        lastRecordedTokenBalance[token] += amount;
        emit VestingCreated(token, amount, block.timestamp);
    }
    
    function getEffectiveEndTime(address token) public view returns (uint256) {
        Vest memory vest = tokenVestings[token];
        if (vest.totalAllocated == 0) return 0;
        return vest.weightedEndTime / vest.totalAllocated;
    }
    
    function _calculateClaimable(address token) internal view returns (uint256) {
        Vest memory vest = tokenVestings[token];
        if (vest.totalAllocated == 0) return 0;
        
        uint256 effectiveEndTime = vest.weightedEndTime / vest.totalAllocated;
        
        if (block.timestamp >= effectiveEndTime) {
            return vest.totalAllocated - vest.totalClaimed;
        }
        
        // Linear vesting from first deposit to weighted end time
        uint256 vestingDuration = effectiveEndTime - vest.lastDepositTime;
        uint256 elapsed = block.timestamp - vest.lastDepositTime;
        
        uint256 vested = (vest.totalAllocated * elapsed) / vestingDuration;
        
        return vested > vest.totalClaimed ? vested - vest.totalClaimed : 0;
    }
}
```

### **Solution 2: Rolling Window Approach**

Each new deposit extends the vesting period for the entire position.

```solidity:vestingvault.sol
// ... existing code ...

contract VestingVault is Initializable, Context, IVestingVault {
    mapping(address => Vest) private tokenVestings;
    
    struct Vest {
        address token;
        uint8 tokenDecimals;
        uint256 totalAllocated;
        uint256 startTime; // Original start time
        uint256 endTime;    // Gets extended with each deposit
        uint256 totalClaimed;
        uint256 claimedBeforeLastDeposit; // Track what was vested before extension
    }
    
    function vestToken(address token, uint256 amount) external override onlyValidPair {
        if(amount == 0) revert InvalidAmount();
        
        uint256 vestingPeriod = vestingVaultFactory.lockingPeriod();
        
        if (!hasVesting[token]) {
            // First deposit
            tokenVestings[token] = Vest({
                token: token,
                tokenDecimals: IERC20Metadata(token).decimals(),
                totalAllocated: amount,
                startTime: block.timestamp,
                endTime: block.timestamp + vestingPeriod,
                totalClaimed: 0,
                claimedBeforeLastDeposit: 0
            });
        } else {
            Vest storage vest = tokenVestings[token];
            
            // Calculate what's vested so far before extending
            uint256 vestedSoFar = _calculateVestedAmount(vest);
            
            // Add new amount and extend vesting period
            vest.totalAllocated += amount;
            vest.endTime = block.timestamp + vestingPeriod; // Reset end time
            vest.claimedBeforeLastDeposit = vestedSoFar;
        }
        
        lastRecordedTokenBalance[token] += amount;
    }
    
    function _calculateVestedAmount(Vest memory vest) internal view returns (uint256) {
        if (block.timestamp >= vest.endTime) {
            return vest.totalAllocated;
        }
        
        // Preserve already vested amount + linear vesting for the rest
        uint256 newVesting = vest.totalAllocated - vest.claimedBeforeLastDeposit;
        uint256 elapsed = block.timestamp - vest.startTime;
        uint256 duration = vest.endTime - vest.startTime;
        
        uint256 newlyVested = (newVesting * elapsed) / duration;
        return vest.claimedBeforeLastDeposit + newlyVested;
    }
}
```

### **Solution 3: Tranche-Based System with Token Aggregation**

Keep separate tranches but organize by token with better aggregation methods.

```solidity:vestingvault.sol
// ... existing code ...

contract VestingVault is Initializable, Context, IVestingVault {
    // Map token to array of vesting indices
    mapping(address => uint256[]) public tokenVestingIndices;
    mapping(uint256 => Vest) private vestings;
    uint256 public vestingCount;
    
    function vestToken(address token, uint256 amount) external override onlyValidPair {
        // Create new vesting as before
        uint256 currentVestingCount = vestingCount;
        vestings[currentVestingCount] = Vest({
            token: token,
            tokenDecimals: IERC20Metadata(token).decimals(),
            totalAllocated: amount,
            startTime: block.timestamp,
            endTime: block.timestamp + vestingVaultFactory.lockingPeriod(),
            totalClaimed: 0
        });
        
        // Track this vesting index for the token
        tokenVestingIndices[token].push(currentVestingCount);
        vestingCount++;
        
        lastRecordedTokenBalance[token] += amount;
        emit VestingCreated(currentVestingCount, token, amount);
    }
    
    // Claim all vestings for a specific token
    function claimTokenByAddress(address token) external {
        if(_msgSender() != user) revert InvalidUser();
        
        uint256[] memory indices = tokenVestingIndices[token];
        for (uint256 i = 0; i < indices.length; i++) {
            _claimTokens(indices[i]);
        }
    }
    
    // Get aggregated info for a token
    function getTokenVestingInfo(address token) external view returns (
        uint256 totalAllocated,
        uint256 totalClaimable,
        uint256 totalClaimed,
        uint256 vestingCount
    ) {
        uint256[] memory indices = tokenVestingIndices[token];
        vestingCount = indices.length;
        
        for (uint256 i = 0; i < indices.length; i++) {
            Vest memory vest = vestings[indices[i]];
            totalAllocated += vest.totalAllocated;
            totalClaimed += vest.totalClaimed;
            totalClaimable += _claimable(indices[i]);
        }
    }
}
```

## Recommendation

I recommend **Solution 1 (Weighted Average)** because it:
- Maintains a single position per token (cleaner state)
- Preserves fairness through weighted averaging
- Reduces gas costs for claims (single position vs multiple)
- Provides intuitive vesting behavior

The key considerations for implementation:
1. Auto-claim vested tokens before adding new deposits to preserve vested rights
2. Use high precision math to avoid rounding errors in weighted calculations
3. Consider adding a minimum deposit amount to prevent gaming the system
4. Add view functions to show users their effective vesting schedule

Would you like me to provide a complete implementation of any of these solutions or help you adapt your existing contract?

```plaintext
// ... existing code ...

contract VestingVault is Initializable, Context, IVestingVault {
    // Modified structure - single vesting per token
    mapping(address => Vest) private tokenVestings;
    
    // Track which tokens have vestings
    address[] public vestedTokens;
    mapping(address => bool) public hasVesting;
    
    // Modified vest structure to handle accumulation
    struct Vest {
        address token;
        uint8 tokenDecimals;
        uint256 totalAllocated;
        uint256 weightedEndTime; // Sum of (amount * endTime) for weighted average
        uint256 totalClaimed;
        uint256 lastDepositTime; // Track most recent deposit
    }
    
    function vestToken(address token, uint256 amount) external override onlyValidPair {
        if(amount == 0) revert InvalidAmount();
        
        uint256 _currentBalance = IERC20(token).balanceOf(address(this));
        if(_currentBalance < lastRecordedTokenBalance[token] + amount) revert InsufficientTokenReceived();
        
        uint256 vestingPeriod = vestingVaultFactory.lockingPeriod();
        uint256 newEndTime = block.timestamp + vestingPeriod;
        
        if (!hasVesting[token]) {
            // First deposit for this token
            tokenVestings[token] = Vest({
                token: token,
                tokenDecimals: IERC20Metadata(token).decimals(),
                totalAllocated: amount,
                weightedEndTime: amount * newEndTime,
                totalClaimed: 0,
                lastDepositTime: block.timestamp
            });
            
            vestedTokens.push(token);
            hasVesting[token] = true;
        } else {
            // Additional deposit for existing token
            Vest storage vest = tokenVestings[token];
            
            // Calculate claimable amount before updating to avoid losing vested tokens
            uint256 currentlyClaimable = _calculateClaimable(token);
            if (currentlyClaimable > 0) {
                // Auto-claim before adding new deposit to preserve vested rights
                _autoClaimBeforeDeposit(token, currentlyClaimable);
            }
            
            // Update weighted average end time
            uint256 newTotalAllocated = vest.totalAllocated + amount;
            vest.weightedEndTime = vest.weightedEndTime + (amount * newEndTime);
            vest.totalAllocated = newTotalAllocated;
            vest.lastDepositTime = block.timestamp;
        }
        
        lastRecordedTokenBalance[token] += amount;
        emit VestingCreated(token, amount, block.timestamp);
    }
    
    function getEffectiveEndTime(address token) public view returns (uint256) {
        Vest memory vest = tokenVestings[token];
        if (vest.totalAllocated == 0) return 0;
        return vest.weightedEndTime / vest.totalAllocated;
    }
    
    function _calculateClaimable(address token) internal view returns (uint256) {
        Vest memory vest = tokenVestings[token];
        if (vest.totalAllocated == 0) return 0;
        
        uint256 effectiveEndTime = vest.weightedEndTime / vest.totalAllocated;
        
        if (block.timestamp >= effectiveEndTime) {
            return vest.totalAllocated - vest.totalClaimed;
        }
        
        // Linear vesting from first deposit to weighted end time
        uint256 vestingDuration = effectiveEndTime - vest.lastDepositTime;
        uint256 elapsed = block.timestamp - vest.lastDepositTime;
        
        uint256 vested = (vest.totalAllocated * elapsed) / vestingDuration;
        
        return vested > vest.totalClaimed ? vested - vest.totalClaimed : 0;
    }
}
```

```plaintext
// ... existing code ...

contract VestingVault is Initializable, Context, IVestingVault {
    mapping(address => Vest) private tokenVestings;
    
    struct Vest {
        address token;
        uint8 tokenDecimals;
        uint256 totalAllocated;
        uint256 startTime; // Original start time
        uint256 endTime;    // Gets extended with each deposit
        uint256 totalClaimed;
        uint256 claimedBeforeLastDeposit; // Track what was vested before extension
    }
    
    function vestToken(address token, uint256 amount) external override onlyValidPair {
        if(amount == 0) revert InvalidAmount();
        
        uint256 vestingPeriod = vestingVaultFactory.lockingPeriod();
        
        if (!hasVesting[token]) {
            // First deposit
            tokenVestings[token] = Vest({
                token: token,
                tokenDecimals: IERC20Metadata(token).decimals(),
                totalAllocated: amount,
                startTime: block.timestamp,
                endTime: block.timestamp + vestingPeriod,
                totalClaimed: 0,
                claimedBeforeLastDeposit: 0
            });
        } else {
            Vest storage vest = tokenVestings[token];
            
            // Calculate what's vested so far before extending
            uint256 vestedSoFar = _calculateVestedAmount(vest);
            
            // Add new amount and extend vesting period
            vest.totalAllocated += amount;
            vest.endTime = block.timestamp + vestingPeriod; // Reset end time
            vest.claimedBeforeLastDeposit = vestedSoFar;
        }
        
        lastRecordedTokenBalance[token] += amount;
    }
    
    function _calculateVestedAmount(Vest memory vest) internal view returns (uint256) {
        if (block.timestamp >= vest.endTime) {
            return vest.totalAllocated;
        }
        
        // Preserve already vested amount + linear vesting for the rest
        uint256 newVesting = vest.totalAllocated - vest.claimedBeforeLastDeposit;
        uint256 elapsed = block.timestamp - vest.startTime;
        uint256 duration = vest.endTime - vest.startTime;
        
        uint256 newlyVested = (newVesting * elapsed) / duration;
        return vest.claimedBeforeLastDeposit + newlyVested;
    }
}
```

```plaintext
// ... existing code ...

contract VestingVault is Initializable, Context, IVestingVault {
    // Map token to array of vesting indices
    mapping(address => uint256[]) public tokenVestingIndices;
    mapping(uint256 => Vest) private vestings;
    uint256 public vestingCount;
    
    function vestToken(address token, uint256 amount) external override onlyValidPair {
        // Create new vesting as before
        uint256 currentVestingCount = vestingCount;
        vestings[currentVestingCount] = Vest({
            token: token,
            tokenDecimals: IERC20Metadata(token).decimals(),
            totalAllocated: amount,
            startTime: block.timestamp,
            endTime: block.timestamp + vestingVaultFactory.lockingPeriod(),
            totalClaimed: 0
        });
        
        // Track this vesting index for the token
        tokenVestingIndices[token].push(currentVestingCount);
        vestingCount++;
        
        lastRecordedTokenBalance[token] += amount;
        emit VestingCreated(currentVestingCount, token, amount);
    }
    
    // Claim all vestings for a specific token
    function claimTokenByAddress(address token) external {
        if(_msgSender() != user) revert InvalidUser();
        
        uint256[] memory indices = tokenVestingIndices[token];
        for (uint256 i = 0; i < indices.length; i++) {
            _claimTokens(indices[i]);
        }
    }
    
    // Get aggregated info for a token
    function getTokenVestingInfo(address token) external view returns (
        uint256 totalAllocated,
        uint256 totalClaimable,
        uint256 totalClaimed,
        uint256 vestingCount
    ) {
        uint256[] memory indices = tokenVestingIndices[token];
        vestingCount = indices.length;
        
        for (uint256 i = 0; i < indices.length; i++) {
            Vest memory vest = vestings[indices[i]];
            totalAllocated += vest.totalAllocated;
            totalClaimed += vest.totalClaimed;
            totalClaimable += _claimable(indices[i]);
        }
    }
}
```

---

**User**

explain these different solutions with an example, it would super helpful if you can explain with the example i shared

---

**Cursor**

Excellent idea! Let me explain each solution using your actual example data. You have 8 separate vestings for the same token `0xd96Af99Bbc1DF687ff207657cc8160383b766006` with different amounts and timestamps.

Let me break down your data first for clarity:

```
Vesting 1: 9.78 tokens,  Start: 1758576311 (Day 0),   End: 1844976311 (Day 1000)
Vesting 2: 1.17 tokens,  Start: 1758760678 (Day 2),   End: 1845160678 (Day 1002) 
Vesting 3: 17.26 tokens, Start: 1758760727 (Day 2),   End: 1845160727 (Day 1002)
Vesting 4: 4.51 tokens,  Start: 1758763388 (Day 2),   End: 1845163388 (Day 1002)
Vesting 5: 3.36 tokens,  Start: 1758763726 (Day 2),   End: 1845163726 (Day 1002)
Vesting 6: 8.85 tokens,  Start: 1758812468 (Day 3),   End: 1845212468 (Day 1003)
Vesting 7: 3.41 tokens,  Start: 1759079696 (Day 6),   End: 1845479696 (Day 1006)
Vesting 8: 8.99 tokens,  Start: 1759079789 (Day 6),   End: 1845479789 (Day 1006)

Total: ~57.33 tokens locked over 6 days
```

Now let's see how each solution would handle this:

## **Solution 1: Weighted Average End Time**

With this approach, instead of 8 separate vestings, you'd have **ONE consolidated position**:

```solidity
// After all 8 deposits, you'd have a single vesting:
tokenVestings[0xd96A...] = {
    token: 0xd96Af99Bbc1DF687ff207657cc8160383b766006,
    tokenDecimals: 18,
    totalAllocated: 57,336,670,089,030,314,340 wei (57.33 tokens),
    weightedEndTime: (9.78 * 1844976311) + (1.17 * 1845160678) + ... // weighted sum
    totalClaimed: 0,
    lastDepositTime: 1759079789
}
```

**How the weighted average works:**

```
Effective End Time = Sum(amount_i * endTime_i) / Total Amount

= (9.78 * 1844976311 + 1.17 * 1845160678 + 17.26 * 1845160727 + 
   4.51 * 1845163388 + 3.36 * 1845163726 + 8.85 * 1845212468 + 
   3.41 * 1845479696 + 8.99 * 1845479789) / 57.33

= 1845161759 (approximately Day 1002.2 from start)
```

**Timeline Example:**
- Day 100: You can claim ~5.73 tokens (10% vested)
- Day 500: You can claim ~28.67 tokens (50% vested)  
- Day 1002: You can claim all 57.33 tokens (100% vested)

**Pros:** Single position, weighted fairness, gas efficient
**Cons:** Complex calculation, later deposits slightly reduce overall vesting time for earlier deposits

## **Solution 2: Rolling Window (Extension) Approach**

Each new deposit **extends the vesting period** for the entire position:

```solidity
// After deposit 1:
vest = {
    totalAllocated: 9.78 tokens,
    startTime: 1758576311,
    endTime: 1844976311,  // Day 1000
    claimedBeforeLastDeposit: 0
}

// After deposit 2 (Day 2):
// First, calculate what's vested from deposit 1: 9.78 * (2/1000) = 0.02 tokens
vest = {
    totalAllocated: 10.95 tokens (9.78 + 1.17),
    startTime: 1758576311,  // Keep original start
    endTime: 1845160678,    // RESET to Day 1002 (new deposit time + 1000)
    claimedBeforeLastDeposit: 0.02 tokens
}

// After all 8 deposits (Day 6):
vest = {
    totalAllocated: 57.33 tokens,
    startTime: 1758576311,
    endTime: 1845479789,    // Day 1006 (last deposit + 1000 days)
    claimedBeforeLastDeposit: 0.34 tokens (what was vested before last deposit)
}
```

**Timeline Example:**
- Day 100: You can claim ~5.7 tokens
- Day 500: You can claim ~28.5 tokens
- Day 1006: You can claim all 57.33 tokens

**Pros:** Simple concept, rewards long-term holders
**Cons:** Later deposits push out vesting for earlier deposits (less fair to early depositors)

## **Solution 3: Tranche-Based with Aggregation**

Keeps your current 8 separate vestings but adds **better organization**:

```solidity
// Token mapping points to all vesting indices
tokenVestingIndices[0xd96A...] = [0, 1, 2, 3, 4, 5, 6, 7]

// Each vesting remains separate (like current implementation)
vestings[0] = { 9.78 tokens, start: Day 0, end: Day 1000 }
vestings[1] = { 1.17 tokens, start: Day 2, end: Day 1002 }
vestings[2] = { 17.26 tokens, start: Day 2, end: Day 1002 }
// ... etc

// But you get aggregated functions:
getTokenVestingInfo(0xd96A...) returns:
{
    totalAllocated: 57.33 tokens,
    totalClaimable: (calculated per vesting),
    totalClaimed: 0,
    vestingCount: 8
}
```

**Timeline Example at Day 500:**
- Vesting 0: 4.89 tokens claimable (50% of 9.78)
- Vesting 1: 0.58 tokens claimable (49.8% of 1.17)
- Vesting 2: 8.59 tokens claimable (49.8% of 17.26)
- ... etc
- **Total claimable: ~28.5 tokens**

**Pros:** Most accurate/fair, preserves exact vesting schedules
**Cons:** Gas expensive (8 separate claims), complex state management

## **Practical Comparison**

Let's say it's **Day 500** and you want to claim:

| Solution | Claimable Amount | Gas Cost | Fairness |
|----------|-----------------|----------|----------|
| **Weighted Average** | ~28.6 tokens | Low (1 calculation) | Good (balanced) |
| **Rolling Window** | ~28.5 tokens | Low (1 calculation) | Poor (early deposits penalized) |
| **Tranche-Based** | ~28.5 tokens | High (8 calculations) | Excellent (exact) |

## **My Recommendation for Your Case**

Given your example where deposits happen over just 6 days but vest for 1000 days, **Solution 1 (Weighted Average)** makes the most sense because:

1. The deposit period (6 days) is tiny compared to vesting period (1000 days)
2. The weighted average end time (Day 1002) is very close to the individual end times (Days 1000-1006)
3. You get massive gas savings with a single position
4. The math is fair to all depositors

Would you like me to show you the complete implementation of the weighted average solution adapted to your existing contract structure?

```plaintext
Vesting 1: 9.78 tokens,  Start: 1758576311 (Day 0),   End: 1844976311 (Day 1000)
Vesting 2: 1.17 tokens,  Start: 1758760678 (Day 2),   End: 1845160678 (Day 1002) 
Vesting 3: 17.26 tokens, Start: 1758760727 (Day 2),   End: 1845160727 (Day 1002)
Vesting 4: 4.51 tokens,  Start: 1758763388 (Day 2),   End: 1845163388 (Day 1002)
Vesting 5: 3.36 tokens,  Start: 1758763726 (Day 2),   End: 1845163726 (Day 1002)
Vesting 6: 8.85 tokens,  Start: 1758812468 (Day 3),   End: 1845212468 (Day 1003)
Vesting 7: 3.41 tokens,  Start: 1759079696 (Day 6),   End: 1845479696 (Day 1006)
Vesting 8: 8.99 tokens,  Start: 1759079789 (Day 6),   End: 1845479789 (Day 1006)

Total: ~57.33 tokens locked over 6 days
```

```plaintext
// After all 8 deposits, you'd have a single vesting:
tokenVestings[0xd96A...] = {
    token: 0xd96Af99Bbc1DF687ff207657cc8160383b766006,
    tokenDecimals: 18,
    totalAllocated: 57,336,670,089,030,314,340 wei (57.33 tokens),
    weightedEndTime: (9.78 * 1844976311) + (1.17 * 1845160678) + ... // weighted sum
    totalClaimed: 0,
    lastDepositTime: 1759079789
}
```

```plaintext
Effective End Time = Sum(amount_i * endTime_i) / Total Amount

= (9.78 * 1844976311 + 1.17 * 1845160678 + 17.26 * 1845160727 + 
   4.51 * 1845163388 + 3.36 * 1845163726 + 8.85 * 1845212468 + 
   3.41 * 1845479696 + 8.99 * 1845479789) / 57.33

= 1845161759 (approximately Day 1002.2 from start)
```

```plaintext
// After deposit 1:
vest = {
    totalAllocated: 9.78 tokens,
    startTime: 1758576311,
    endTime: 1844976311,  // Day 1000
    claimedBeforeLastDeposit: 0
}

// After deposit 2 (Day 2):
// First, calculate what's vested from deposit 1: 9.78 * (2/1000) = 0.02 tokens
vest = {
    totalAllocated: 10.95 tokens (9.78 + 1.17),
    startTime: 1758576311,  // Keep original start
    endTime: 1845160678,    // RESET to Day 1002 (new deposit time + 1000)
    claimedBeforeLastDeposit: 0.02 tokens
}

// After all 8 deposits (Day 6):
vest = {
    totalAllocated: 57.33 tokens,
    startTime: 1758576311,
    endTime: 1845479789,    // Day 1006 (last deposit + 1000 days)
    claimedBeforeLastDeposit: 0.34 tokens (what was vested before last deposit)
}
```

```plaintext
// Token mapping points to all vesting indices
tokenVestingIndices[0xd96A...] = [0, 1, 2, 3, 4, 5, 6, 7]

// Each vesting remains separate (like current implementation)
vestings[0] = { 9.78 tokens, start: Day 0, end: Day 1000 }
vestings[1] = { 1.17 tokens, start: Day 2, end: Day 1002 }
vestings[2] = { 17.26 tokens, start: Day 2, end: Day 1002 }
// ... etc

// But you get aggregated functions:
getTokenVestingInfo(0xd96A...) returns:
{
    totalAllocated: 57.33 tokens,
    totalClaimable: (calculated per vesting),
    totalClaimed: 0,
    vestingCount: 8
}
```

