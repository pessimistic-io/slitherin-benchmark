// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.12;

// Inheritance
import "./UUPSUpgradeable.sol";
import "./Initializable.sol";
import "./OwnableUpgradeable.sol";
import { IERC20Upgradeable } from "./IERC20Upgradeable.sol";
import { SafeERC20Upgradeable } from "./SafeERC20Upgradeable.sol";
import { IERC20Metadata } from "./extensions_IERC20Metadata.sol";
import "./IStakingRewards.sol";

/// @title Staking reward contract
/// @author Steer Protocol
/// @dev This contract is used to reward stakers for their staking time.
contract StakingRewards is
    IStakingRewards,
    Initializable,
    OwnableUpgradeable,
    UUPSUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    // Storage

    // Constants
    uint256 public constant PRECISION = 1e18;
    uint256 public constant SECONDS_IN_YEAR = 31_536_000;
    uint256 public constant RATE_PRECISION = 100_00; //Precision for reward calculaion

    // Mapping of Pool details to pool id
    mapping(uint256 => Pool) public pools;

    // Total no. of pools created
    uint256 public totalPools;

    //Mapping of user details per pool
    mapping(uint256 => mapping(address => UserInfo)) public userInfoPerPool;

    // Mapping of total rewards allocated currently for a pool
    mapping(uint256 => uint256) public totalRewardsPerPool;

    // Mapping that returns the state of pool by passing pool id, true means staking is paused and false means staking is allowed
    mapping(uint256 => bool) public isPaused;

    // Mapping that returns pending rewards for a particular user for a particular pool
    mapping(address => mapping(uint256 => uint256)) public pendingRewards;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer() {}

    // External Functions

    /// @dev To stake tokens
    /// @param amount The number of tokens to be staked.
    /// @param poolId The id of the pool in which tokens should be staked.
    function stake(uint256 amount, uint256 poolId) external {
        _stake(msg.sender, amount, poolId);
    }

    /// @dev To stake tokens
    /// @param user The address that stake tokens for.
    /// @param amount The number of tokens to be staked.
    /// @param poolId The id of the pool in which tokens should be staked.
    function stakeFor(address user, uint256 amount, uint256 poolId) external {
        _stake(user, amount, poolId);
    }

    /// @dev To unstake staked tokens.
    /// @param poolId The id of pool from which the tokens whould be unstaked.
    function unstake(uint256 poolId) external {
        Pool memory pool = pools[poolId];
        UserInfo storage userInfo = userInfoPerPool[poolId][msg.sender];
        uint256 amount = userInfo.balance;
        require(amount != 0, "0 Stake");
        pools[poolId].totalAmount -= amount;
        if (block.timestamp > pool.end) {
            claimReward(poolId, pool, userInfo);
        } else {
            userInfo.lastRewarded = 0;
            userInfo.rewards = 0;
            userInfo.balance = 0;
        }
        IERC20Upgradeable(pool.stakingToken).safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount, poolId);
    }

    /// @dev To claim the pending rewards
    /// @param poolId The id of the pool from which the pending rewards should be claimed
    function claimPendingRewards(uint256 poolId) external {
        uint256 pending = pendingRewards[msg.sender][poolId];
        pendingRewards[msg.sender][poolId] = 0;
        totalRewardsPerPool[poolId] -= pending;
        IERC20Upgradeable(pools[poolId].rewardToken).safeTransfer(
            msg.sender,
            pending
        );
    }

    // Internal Functions

    function claimReward(
        uint256 poolId,
        Pool memory pool,
        UserInfo storage userInfo
    ) internal {
        updateReward(pool, userInfo);
        uint256 reward = userInfo.rewards;
        userInfo.rewards = 0;
        userInfo.balance = 0;
        userInfo.lastRewarded = 0;
        uint256 totalRewards = totalRewardsPerPool[poolId];
        if (totalRewards >= reward) {
            totalRewardsPerPool[poolId] = totalRewards - reward;
            emit RewardPaid(msg.sender, poolId, reward);
            IERC20Upgradeable(pool.rewardToken).safeTransfer(
                msg.sender,
                reward
            );
        } else {
            pendingRewards[msg.sender][poolId] = reward - totalRewards;
            totalRewardsPerPool[poolId] = 0;
            emit RewardPaid(msg.sender, poolId, totalRewards);
            IERC20Upgradeable(pool.rewardToken).safeTransfer(
                msg.sender,
                totalRewards
            );
        }
    }

    function updateReward(
        Pool memory pool,
        UserInfo storage userInfo
    ) internal {
        uint256 stakeTime;
        if (block.timestamp > pool.end) stakeTime = pool.end;
        else stakeTime = block.timestamp;
        uint256 balance = userInfo.balance;
        uint256 lastReward;
        if (balance != 0) {
            lastReward =
                (balance *
                    (((stakeTime - userInfo.lastRewarded) *
                        (pool.rewardRate * PRECISION)) /
                        (RATE_PRECISION * SECONDS_IN_YEAR))) /
                PRECISION;
            userInfo.rewards += lastReward;
        }
        userInfo.lastRewarded = stakeTime;
    }

    /// @dev To stake tokens
    /// @param user The address that stake tokens for.
    /// @param amount The number of tokens to be staked.
    /// @param poolId The id of the pool in which tokens should be staked.
    function _stake(address user, uint256 amount, uint256 poolId) internal {
        // Validate
        require(amount > 0, "Cannot stake 0");
        Pool memory pool = pools[poolId];
        UserInfo storage userInfo = userInfoPerPool[poolId][user];
        require(pool.start <= block.timestamp, "Staking not started");
        require(!isPaused[poolId], "Staking Paused");
        require(block.timestamp < pool.end, "Staking Period is over");
        // Update values before staking
        updateReward(pool, userInfo);

        // Stake
        userInfo.balance += amount;
        pools[poolId].totalAmount += amount;
        IERC20Upgradeable(pool.stakingToken).safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );
        emit Staked(user, amount, poolId);
    }

    //Public functions
    function initialize() public initializer {
        __UUPSUpgradeable_init();
        __Ownable_init();
    }

    // View Functions

    /// @dev To get rewards for a particular address for a particular pool
    /// @param account The address of the account whose reward is to be fetched
    /// @param poolId The id of the pool from which rewards for the account needs to be fetched
    function getRewardsForAPool(
        address account,
        uint256 poolId
    ) external view returns (uint256) {
        Pool memory pool = pools[poolId];
        UserInfo memory userInfo = userInfoPerPool[poolId][account];
        uint256 stakeTime;
        if (block.timestamp > pool.end) stakeTime = pool.end;
        else stakeTime = block.timestamp;
        uint256 currentReward = (userInfo.balance *
            (((stakeTime - userInfo.lastRewarded) *
                (pool.rewardRate * PRECISION)) /
                (RATE_PRECISION * SECONDS_IN_YEAR))) / PRECISION;
        currentReward += userInfo.rewards;
        return currentReward;
    }

    /// @dev To get the pool for given id
    /// @return Pool which has the details for every pool
    function getPool(uint256 poolId) public view returns (Pool memory) {
        return pools[poolId];
    }

    /// @dev To get the details for all pools
    /// @return pools which has the details for every pool
    function getPools() public view returns (Pool[] memory, string[] memory) {
        uint256 _totalPools = totalPools;
        Pool[] memory _pools = new Pool[](_totalPools);
        string[] memory symbols = new string[](_totalPools);
        for (uint256 i; i != _totalPools; ++i) {
            _pools[i] = pools[i];
            string memory stakingTokenSymbol = IERC20Metadata(
                _pools[i].stakingToken
            ).symbol();
            string memory rewardTokenSymbol = IERC20Metadata(
                _pools[i].rewardToken
            ).symbol();
            symbols[i] = string(
                abi.encodePacked(stakingTokenSymbol, "/", rewardTokenSymbol)
            );
        }
        return (_pools, symbols);
    }

    function getBalances(
        address user
    ) external view returns (uint256[] memory) {
        uint256 _totalPools = totalPools;
        uint256[] memory _balances = new uint256[](_totalPools);
        for (uint256 i; i != _totalPools; ++i)
            _balances[i] = userInfoPerPool[i][user].balance;
        return _balances;
    }

    //Only Owner functions

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    /// @dev To create a staking pool
    /// @param stakingToken Address of the token that will be staked
    /// @param rewardToken Address of the token that will be given as reward
    /// @param rewardRate Rate at which the rewards will be calculated yearly and then multiplied by 100
    /// @param start Start time of the staking pool
    /// @param end Ending time for the staking pool
    function createPool(
        address stakingToken,
        address rewardToken,
        uint256 rewardRate,
        uint256 start,
        uint256 end
    ) external onlyOwner {
        uint256 _totalPools = totalPools;
        require(start < end, "TIME");
        require(stakingToken != rewardToken, "SAME");
        pools[_totalPools] = Pool({
            stakingToken: stakingToken,
            rewardToken: rewardToken,
            rewardRate: rewardRate * 100,
            totalAmount: 0,
            start: start,
            end: end
        });
        totalPools = _totalPools + 1;
    }

    /// @dev To pause or resume a particular staking pool
    /// @param poolId The id of the staking pool that should be paused or resumed
    /// @param pause The boolean where passing true means pause the pool
    ///              and passing false means resume the pool
    function setJobState(uint256 poolId, bool pause) external onlyOwner {
        isPaused[poolId] = pause;
    }

    /// @dev To deposit reward tokens that will be given to the stakers.
    /// @param poolId The id of the pool in which rewards should be allocated
    /// @param amount The value of tokens that should be added to give out as rewards.
    function depositRewards(uint256 poolId, uint256 amount) external {
        totalRewardsPerPool[poolId] += amount;
        emit RewardsDeposited(msg.sender, poolId, amount);
        IERC20Upgradeable(pools[poolId].rewardToken).safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );
    }

    /// @dev To withdraw the extra rewards that remains on the contract
    ///      and can only be called by owner of this contract.
    /// @param poolId The id of the pool in which rewards should be withdrawn
    /// @param amount The value of tokens that should be removed from the contract.
    /// @param receiver The address where the withdrawn tokens should be sent
    function withdrawRewards(
        uint256 poolId,
        uint256 amount,
        address receiver
    ) external onlyOwner {
        // Reduce totalRewards by amount.
        // Owner cannot withdraw more rewards than they have deposited.
        totalRewardsPerPool[poolId] -= amount;
        emit RewardsWithdrawn(amount, poolId);
        IERC20Upgradeable(pools[poolId].rewardToken).safeTransfer(
            receiver,
            amount
        );
    }
}

