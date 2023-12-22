// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./ReentrancyGuard.sol";
import "./AccessControl.sol";
import "./SafeERC20.sol";
import "./EnumerableSet.sol";

import "./IOriginalMintersPool.sol";

contract OriginalMintersPool is IOriginalMintersPool, ReentrancyGuard, AccessControl {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;
    
    uint256 public constant REWARDS_DURATION = 7 days;
    bytes32 public constant ETHEREAL_SPHERES_ROLE = keccak256("ETHEREAL_SPHERES_ROLE");
    bytes32 public constant REWARD_PROVIDER_ROLE = keccak256("REWARD_PROVIDER_ROLE");

    uint256 public totalStake;
    uint256 public rewardRate;
    uint256 public storedRewardPerToken;
    uint256 public lastUpdateTime;
    uint256 public periodFinish;
    IERC20 public immutable weth;

    EnumerableSet.AddressSet private _originalMinters;

    mapping(address => uint256) public stakeByAccount;
    mapping(address => uint256) public storedRewardByAccount;
    mapping(address => uint256) public rewardPerTokenPaidByAccount;

    /// @param weth_ Wrapped Ether contract address.
    /// @param etherealSpheres_ EtherealSpheres contract address.
    /// @param royaltyDistributor_ RoyaltyDistributor contract address.
    constructor(IERC20 weth_, address etherealSpheres_, address royaltyDistributor_) {
        weth = weth_;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ETHEREAL_SPHERES_ROLE, etherealSpheres_);
        _grantRole(REWARD_PROVIDER_ROLE, msg.sender);
        _grantRole(REWARD_PROVIDER_ROLE, royaltyDistributor_);
    }

    /// @inheritdoc IOriginalMintersPool
    function updateStakeFor(address account_, uint256 summand_) external onlyRole(ETHEREAL_SPHERES_ROLE) {
        _updateReward(account_);
        unchecked {
            stakeByAccount[account_] += summand_;
            totalStake += summand_;
        }
    }

    /// @inheritdoc IOriginalMintersPool
    function provideReward(uint256 reward_) external onlyRole(REWARD_PROVIDER_ROLE) {
        _updateReward(address(0));
        if (block.timestamp >= periodFinish) {
            unchecked {
                rewardRate = reward_ / REWARDS_DURATION;
            }
        } else {
            unchecked {
                uint256 leftover = (periodFinish - block.timestamp) * rewardRate;
                rewardRate = (reward_ + leftover) / REWARDS_DURATION;
            }
        }
        if (rewardRate > weth.balanceOf(address(this)) / REWARDS_DURATION) {
            revert ProvidedRewardTooHigh();
        }
        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp + REWARDS_DURATION;
        emit RewardProvided(reward_);
    }

    /// @inheritdoc IOriginalMintersPool
    function getReward() public nonReentrant {
        _updateReward(msg.sender);
        uint256 reward = storedRewardByAccount[msg.sender];
        if (reward > 0) {
            storedRewardByAccount[msg.sender] = 0;
            weth.safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    /// @inheritdoc IOriginalMintersPool
    function lastTimeRewardApplicable() public view returns (uint256) {
        uint256 m_periodFinish = periodFinish;
        return block.timestamp < m_periodFinish ? block.timestamp : m_periodFinish;
    }

    /// @inheritdoc IOriginalMintersPool
    function rewardPerToken() public view returns (uint256) {
        uint256 m_totalStake = totalStake;
        if (m_totalStake == 0) {
            return storedRewardPerToken;
        }
        return
            (lastTimeRewardApplicable() - lastUpdateTime)
            * rewardRate
            * 1e18
            / m_totalStake
            + storedRewardPerToken;
    }

    /// @inheritdoc IOriginalMintersPool
    function earned(address account_) public view returns (uint256) {
        return
            stakeByAccount[account_]
            * (rewardPerToken() - rewardPerTokenPaidByAccount[account_])
            / 1e18
            + storedRewardByAccount[account_];
    }

    /// @notice Updates the earned reward by `account_`.
    /// @param account_ Account address.
    function _updateReward(address account_) private {
        storedRewardPerToken = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account_ != address(0)) {
            storedRewardByAccount[account_] = earned(account_);
            rewardPerTokenPaidByAccount[account_] = storedRewardPerToken;
        }
    }
}
