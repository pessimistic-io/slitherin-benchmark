//SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./interfaces_IERC20.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";
import "./Ownable.sol";
import "./IElleriumTokenERC20.sol";

/// Insufficient value. 
/// Minimum `minimum` but only `attempt` provided.
/// @param attempt value provided.
/// @param minimum minimum value.
error InsufficientValue(uint256 attempt, uint256 minimum);

/// Value too large. Maximum `maximum` but `attempt` provided.
/// @param attempt balance available.
/// @param maximum maximum value.
error ValueOverflow(uint256 attempt, uint256 maximum); 

/// @title Allows stakingToken to be staked and unstaked, accruing rewardsToken.
/// @author Wayne (Ellerian Prince)
/// @notice Allows $MLP ($ELM-$MAGIC LP Tokens) to be staked to accumulate $ELM rewards.
/// @dev Stakers receive % proportionate to their staked tokens in the pool.
contract ElleriumLPStakingPool is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Total LP tokens staked in WEI.
    uint256 public totalStaked;

    /// @notice Address of the ERC20 reward token.
    IElleriumTokenERC20 public rewardsToken;

    /// @notice Address of the ERC20 staked token.
    IERC20 public stakingToken;

    /// @notice Address holding staking fees.
    address public stakingLPFeesAddress = 0x69832Af74774baE99D999e7F74FE3F7d5833bF84;

    /// @notice Minimum amount to be a valid stake (1 Ether).
    uint256 public minimumStakeAmount = 1 * 1e18;

    /// @notice Reward rate for emissions in WEI. (default 500 ELM per day).
    uint256 public rewardRate = 5787036000000000;

    /// @dev Last rewardPerToken() update time.
    uint256 private lastUpdateTime;

    /// @dev Last rewardPerToken() update time.
    uint256 private rewardPerTokenStored;

    /// @dev Mapping from user address to their last updated individual rewardPerToken.
    mapping(address => uint256) private userRewardPerTokenPaid;

    /// @dev Mapping from user address to their total $ELM rewards.
    mapping(address => uint256) private totalRewards;

    /// @dev Mapping from user address to their $MLP balances.
    mapping(address => uint256) private balances;

    /// @dev Mapping from user address to their latest deposit time.
    mapping(address => uint256) private latestDepositTime;

    /// @dev Are fees in effect?
    bool public applyFees = true;

    /// @dev Fee timing intervals. Each index represents the interval in seconds.
    uint256[] public feesInterval = [60, 3600, 86400, 259200, 604800, 2592000];

    /// @dev Initializes dependencies.
    /// @param _stakingToken ERC20 token to be staked.
    /// @param _rewardsToken ERC20 token to be rewarded.
    constructor(address _stakingToken, address _rewardsToken) {
        stakingToken = IERC20(_stakingToken);
        rewardsToken = IElleriumTokenERC20(_rewardsToken);
    }

    /// @notice Exposes withdrawal fees based on sender's last deposit timing.
    /// @dev Results need to be / 100 to give its % representation.
    /// @return Withdrawal fees.
    function getWithdrawalFees() public view returns (uint256) {
        uint256 timeDifference = block.timestamp - latestDepositTime[msg.sender];
        if (applyFees) {
            if (timeDifference <= feesInterval[0]) { // 50% slashing fee
                return 5000;
            } else if (timeDifference <= feesInterval[1]) { // 20% if before 1st hour.
                return 2000;
            } else if (timeDifference <= feesInterval[2]) { // 10% if before 1st day.
                return 1000;
            } else if (timeDifference <= feesInterval[3]) { // 5% if before 3 days.
                return 500;
            } else if (timeDifference <= feesInterval[4]) { // 3% if before 1 week.
                return 300;
            } else if (timeDifference <= feesInterval[5]) { // 1% if before 1 month.
                return 100;
            }
            return 50;
        }
        return 0;        
    }

    /// @notice (Owner Only) Sets the rewardsToken accumulation rate.
    /// @dev Changing this does not affect accrued rewards.
    /// @param _emissionRateInWEI New emission rate, in WEI.
    /// @param _isFeesApply Should fees be taken?
    function setRewardRate(uint256 _emissionRateInWEI, bool _isFeesApply) external onlyOwner {
        rewardRate = _emissionRateInWEI;
        applyFees = _isFeesApply;
    }

    /// @notice Exposes sender's last deposit timing.
    /// @return Timestamp of last deposit.
    function getLastDepositTime() external view returns (uint256) {
         return latestDepositTime[msg.sender];
    }

    /// @notice Exposes stakingToken balance of an address.
    /// @return stakingToken balance of the address in WEI.
    function balanceOf(address _account) external view returns (uint256) {
        return balances[_account];
    }

    /// @notice Exposes sender's claimable rewardToken balance.
    /// @return Sender's Claimable rewardToken balance in WEI.
    function checkTotalRewards() external view returns (uint256) {
        return totalRewards[msg.sender];
    }

    /// @notice Exposes value to be accrued by a single token unit since last update.
    /// @return Value to be accrued by a single token unit.
    /// @dev Called in updateReward modifier.
    function rewardPerToken() public view returns (uint256) {
        if (totalStaked == 0) {
            return rewardPerTokenStored;
        }
        return
            rewardPerTokenStored + (block.timestamp - lastUpdateTime) * rewardRate * 1e18 / totalStaked;
    }

    /// @notice Exposes rewards accrued by a specified address.
    /// @return Rewards accrued by the specified address.
    /// @dev Called in updateReward modifier.
    function earned(address account) public view returns (uint256) {
        return 
        balances[account] * (rewardPerToken() - userRewardPerTokenPaid[account]) / 1e18 + totalRewards[account];
    }

    /// @notice Sends stakedTokens into the contract to start accruing rewardTokens.
    /// @dev Tokens are held in the contract until unstaked. 
    ///      This changes the value of a single token unit, updateReward modifier is called.
    function stake(uint256 _amount) external nonReentrant updateReward(msg.sender) {
        // Must deposit minimum 1 Ether.
        if (_amount < minimumStakeAmount) {
            revert InsufficientValue(_amount, minimumStakeAmount);
        }
        
        // Transfer tokens into this contract.
        stakingToken.safeTransferFrom(msg.sender, address(this), _amount);

        // Update sender and pool's balances, deposit timing.
        totalStaked += _amount;
        balances[msg.sender] += _amount;
        latestDepositTime[msg.sender] = block.timestamp;

        // Emit Staked event for indexing.
        emit Staked(msg.sender, _amount);
    }

    /// @notice Retrieve deposited stakedTokens without claiming rewards.
    /// @dev This changes the value of a single token unit, updateReward modifier is called.
    function unstake(uint256 _amount) public nonReentrant updateReward(msg.sender) {
        // Can only withdraw within balances.
        if (_amount > balances[msg.sender]) {
            revert ValueOverflow(_amount, balances[msg.sender]);
        }

        // Update sender and pool's balances.
        totalStaked -= _amount;
        balances[msg.sender] -= _amount;        

        // Calculate tax if necessary.
        if (applyFees) {
            // Divide by 100 to calculate in %, then by another 100 to get the actual %
            uint256 taxFee = _amount * getWithdrawalFees() / 10000;

            // Transfer tokens from this contract back to the sender, taking a fee if enabled.
            stakingToken.safeTransfer(stakingLPFeesAddress, taxFee);
            stakingToken.safeTransfer(msg.sender, _amount - taxFee);
        } else {
            // Send full amount back to sender.
            stakingToken.safeTransfer(msg.sender, _amount);
        }

        // Emit Unstaked event for indexing.
        emit Unstaked(msg.sender, _amount);
    }

    /// @notice Claims accrued rewards.
    /// @dev Rewards are minted from rewardToken. This contract needs to have perms to mint.
    function getReward() public nonReentrant updateReward(msg.sender) {
        uint256 reward = totalRewards[msg.sender];
        if (reward > 0) {
            totalRewards[msg.sender] = 0;

            rewardsToken.mint(msg.sender, reward);
            emit ClaimedReward(msg.sender, reward);
        }
    }

    /// @notice Allows a user to retrieve all his stakedTokens and claim accrued rewards together.
    function unstakeAll() external {
        uint256 balance = balances[msg.sender];
        unstake(balance);
        getReward();
    }

    /// @dev Updates rewardPerToken globally using the totalBalance and the earned rewards for an account.
    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = block.timestamp;

        totalRewards[account] = earned(account);
        userRewardPerTokenPaid[account] = rewardPerTokenStored;
        _;
    }

    /// @notice Event emitted when $ELM rewards are claimed.
    /// @param from The address of the caller.
    /// @param value The value of the claimed reward in WEI.
    event ClaimedReward(address indexed from, uint256 value);

    /// @notice Event emitted when $MLP balance increases.
    /// @param from The address of the caller.
    /// @param value The value of the stake in WEI.
    event Staked(address indexed from, uint256 value);

    /// @notice Event emitted when $MLP balance decreases.
    /// @param from The address of the caller.
    /// @param value The value of the unstake in WEI.
    event Unstaked(address indexed from, uint256 value);
}
