// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

//interfaces
import {IUniswapV2Factory} from "../v2-core/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Pair} from "../v2-core/interfaces/IUniswapV2Pair.sol";
import {IVestingVaultFactory} from "./interfaces/IVestingVaultFactory.sol";
import {IVestingVault} from "./interfaces/IVestingVault.sol";

/**
 * @title VestingVault
 * @author Arcane Labs
 * @notice A vesting vault contract that locks tokens for a specific period and releases them linearly over time
 * @dev Each user has their own vault instance that can hold multiple token vestings
 *      Tokens are locked for defined days with linear release
 *      Only valid Uniswap V2 pairs can create vestings in this vault
 */
contract VestingVault is Initializable, Context, IVestingVault {

    /// @notice The user who owns this vesting vault
    address public override user;

    /// @notice Reference to the Uniswap V2 Factory contract
    IUniswapV2Factory private uniswapV2Factory;
    
    /// @notice Reference to the Vesting Vault Factory contract
    IVestingVaultFactory private vestingVaultFactory;

    /// @notice Mapping from vesting index to vesting details
    mapping (uint256 => Vest) private vestings; 
    
    /// @notice Total number of vestings created in this vault
    uint256 public override vestingCount;

    /// @notice Mapping from token address to last recorded token balance
    mapping (address => uint256) public lastRecordedTokenBalance;

    /**
     * @notice Modifier to ensure only valid Uniswap V2 pairs can call certain functions
     * @dev Validates that the caller is a legitimate Uniswap V2 pair contract
     */
    modifier onlyValidPair(){
        address token0 = IUniswapV2Pair(_msgSender()).token0();
        address token1 = IUniswapV2Pair(_msgSender()).token1();
        if(uniswapV2Factory.getPair(token0, token1) != _msgSender()) revert InvalidPair();
        _;
    }

    /**
     * @notice Initializes the vesting vault for a specific user
     * @dev This function can only be called once due to the initializer modifier
     * @param _uniswapV2Factory Address of the Uniswap V2 Factory contract
     * @param _user Address of the user who owns this vault
     */
    function initialize(address _uniswapV2Factory, address _user) external initializer {
        uniswapV2Factory = IUniswapV2Factory(_uniswapV2Factory);
        vestingVaultFactory = IVestingVaultFactory(_msgSender());
        user = _user;
    }

    /**
     * @notice Creates a new vesting entry for a token
     * @dev Only valid Uniswap V2 pairs can call this function
     * @param token Address of the token to vest
     * @param amount Amount of tokens to vest
     * @custom:emits VestingCreated when a new vesting is successfully created
     */
    function vestToken(address token, uint256 amount) external override onlyValidPair {
        if(amount == 0) revert InvalidAmount();

        uint256 _currentBalance = IERC20(token).balanceOf(address(this));
        if(_currentBalance < lastRecordedTokenBalance[token] + amount) revert InsufficientTokenReceived();

        uint256 currentVestingCount = vestingCount;

        vestings[currentVestingCount] = Vest({
            token: token,
            tokenDecimals: IERC20Metadata(token).decimals(),
            totalAllocated: amount,
            startTime: block.timestamp,
            endTime: block.timestamp + vestingVaultFactory.lockingPeriod(),
            totalClaimed: 0
        });
        vestingCount++;

        lastRecordedTokenBalance[token] += amount;

        emit VestingCreated(currentVestingCount, token, amount);

    }

    /**
     * @notice Claims available tokens from a specific vesting
     * @dev Only the vault owner can claim tokens
     * @param vestingIndex Index of the vesting to claim tokens from
     * @custom:emits TokensClaimed when tokens are successfully claimed
     */
    function claimTokens(uint256 vestingIndex) external override {
        if(_msgSender() != user) revert InvalidUser();
        _claimTokens(vestingIndex);        
    }   

    /**
     * @notice Claims all available tokens from all vestings in this vault
     * @dev Only the vault owner can claim tokens. Iterates through all vestings and claims available tokens
     * @custom:emits TokensClaimed for each vesting where tokens are claimed
     */
    function claimAllTokens() external override{
        if(_msgSender() != user) revert InvalidUser();

        for (uint256 i = 0; i < vestingCount; i++) {
            _claimTokens(i);
        }
    }

    /**
     * @notice Internal function to claim tokens from a specific vesting
     * @dev Updates the total claimed amount and transfers tokens to the user
     * @param vestingIndex Index of the vesting to claim tokens from
     */
    function _claimTokens(uint256 vestingIndex) internal {
        uint256 claimableAmount = _claimable(vestingIndex);
        if(claimableAmount == 0) return;

        address _token = vestings[vestingIndex].token;

        lastRecordedTokenBalance[_token] -= claimableAmount;

        vestings[vestingIndex].totalClaimed += claimableAmount;
        SafeERC20.safeTransfer(IERC20(_token), user, claimableAmount);

        emit TokensClaimed(vestingIndex, _token, claimableAmount);
    }

    /**
     * @notice Gets the amount of claimable tokens for a specific vesting
     * @param vestingIndex Index of the vesting to check
     * @return Amount of tokens that can be claimed
     */
    function getClaimableTokens(uint256 vestingIndex) external view override returns (uint256) {
        return _claimable(vestingIndex);
    }

    /**
     * @notice Gets the total claimable amount for a specific token across all vestings
     * @param tokenAddress Address of the token to check
     * @return totalClaimable Total amount of the specified token that can be claimed
     */
    function getClaimableTokensByAddress(address tokenAddress) external view override returns (uint256 totalClaimable) {
        for (uint256 i = 0; i < vestingCount; i++) {
            if (vestings[i].token == tokenAddress) {
                totalClaimable += _claimable(i);
            }
        }
        return totalClaimable;
    }

    /**
     * @notice Gets claimable amounts for all vestings in this vault
     * @return claimableAmounts Array of claimable amounts corresponding to each vesting index
     */
    function getAllClaimableTokens() external view override returns (uint256[] memory claimableAmounts) {
        claimableAmounts = new uint256[](vestingCount);
        for (uint256 i = 0; i < vestingCount; i++) {
            claimableAmounts[i] = _claimable(i);
        }
        return claimableAmounts;
    }

    /**
     * @notice Gets detailed information about a specific vesting
     * @param vestingIndex Index of the vesting to retrieve
     * @return Vest struct containing all vesting details
     */
    function getVesting(uint256 vestingIndex) external view override returns (Vest memory) {
        return vestings[vestingIndex];
    }

    /**
     * @notice Gets detailed information about all vestings in this vault
     * @return Array of Vest structs containing all vesting details
     */
    function getAllVestings() external view override returns (Vest[] memory) {
        Vest[] memory allVestings = new Vest[](vestingCount);
        for (uint256 i = 0; i < vestingCount; i++) {
            allVestings[i] = vestings[i];
        }
        return allVestings;
    }

    /**
     * @notice Internal function to calculate claimable tokens for a specific vesting
     * @dev Implements linear vesting over the full vesting period with second-based precision
     *      Formula: (totalAllocated * secondsElapsed) / totalVestingDuration - totalClaimed
     *      This approach eliminates integer division precision issues and provides smooth linear distribution
     * @param vestingIndex Index of the vesting to calculate claimable amount for
     * @return Amount of tokens that can be claimed at the current time
     */
    function _claimable(uint256 vestingIndex) internal view returns (uint256) {
        Vest memory vest = vestings[vestingIndex];

        // If vesting hasn't started or doesn't exist, no tokens are claimable
        if (vest.startTime == 0 || block.timestamp < vest.startTime) {
            return 0;
        }

        // If vesting has ended, all remaining tokens are claimable
        if (block.timestamp >= vest.endTime) {
            return vest.totalAllocated - vest.totalClaimed;
        }

        // Calculate seconds elapsed since vesting started
        uint256 secondsElapsed = block.timestamp - vest.startTime;
        uint256 totalVestingDuration = vest.endTime - vest.startTime;

        // Calculate total tokens that should be unlocked by now using precise linear distribution
        uint256 totalUnlocked = (vest.totalAllocated * secondsElapsed) / totalVestingDuration;
        
        // Ensure we never unlock more than allocated 
        if (totalUnlocked > vest.totalAllocated) {
            totalUnlocked = vest.totalAllocated;
        }
        
        // prevents double claiming as totalClaimed increases with each claim
        if (totalUnlocked <= vest.totalClaimed) {
            return 0;
        }
        
        return totalUnlocked - vest.totalClaimed;
    }

}