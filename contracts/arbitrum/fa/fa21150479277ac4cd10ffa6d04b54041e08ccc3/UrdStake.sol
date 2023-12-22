// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.17;

import { SafeERC20, IERC20 } from "./SafeERC20.sol";
import { ERC20 } from "./ERC20.sol";
import { OwnableUpgradeable } from "./OwnableUpgradeable.sol";
import { Initializable } from "./Initializable.sol";
import { IUrdStake } from "./IUrdStake.sol";

/**
 * @title UrdStake
 * @notice Contract to stake UR token and earn URO reward.
 * @author Urd
 */
contract UrdStake is Initializable, OwnableUpgradeable, IUrdStake {
    using SafeERC20 for IERC20;

    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
    }

    uint256 private constant ACC_REWARD_PRECISION = 1e12;
    uint256 private constant MAX_REWARD_PER_SECOND = 1 ether;
    uint256 private constant MAX_BOOSTED_REWARD_PER_SECOND = 1 ether;

    IERC20 public URD;
    IERC20 public URO;

    uint256 public rewardPerSecond;
    uint256 public accRewardPerShare;
    uint256 public lastRewardTime;

    mapping(address => UserInfo) public userInfo;

    /**
     * @dev Called by the proxy contract
     *
     */
    function initialize(address _urd, address _uro, uint256 _rewardPerSecond) external initializer {
        __Ownable_init();
        require(_rewardPerSecond <= MAX_REWARD_PER_SECOND, "> MAX_REWARD_PER_SECOND");
        require(_urd != address(0), "Invalid URD address");
        require(_uro != address(0), "Invalid URO address");
        URD = IERC20(_urd);
        URO = IERC20(_uro);
        rewardPerSecond = _rewardPerSecond;
    }

    /* ========== VIEW FUNCTIONS ========== */

    /**
     * @dev Return the total rewards pending to claim by an staker
     * @param _to The user address
     * @return The rewards
     */
    function pendingReward(address _to) external view returns (uint256) {
        UserInfo storage user = userInfo[_to];
        uint256 urdSupply = URD.balanceOf(address(this));
        uint256 _accRewardPerShare = accRewardPerShare;
        if (block.timestamp > lastRewardTime && urdSupply != 0) {
            uint256 time = block.timestamp - lastRewardTime;
            uint256 reward = time * rewardPerSecond;
            _accRewardPerShare += ((reward * ACC_REWARD_PRECISION) / urdSupply);
        }
        return ((user.amount * _accRewardPerShare) / ACC_REWARD_PRECISION) - user.rewardDebt;
    }

    /* ========== PUBLIC FUNCTIONS ========== */

    /**
     * @dev Staked URD tokens, and start earning rewards
     * @param _to Address to stake to
     * @param _amount Amount to stake
     */
    function stake(address _to, uint256 _amount) external override {
        require(_amount != 0, "INVALID_AMOUNT");
        UserInfo storage user = userInfo[_to];

        update();

        if (user.amount != 0) {
            uint256 pending = (user.amount * accRewardPerShare) / ACC_REWARD_PRECISION - user.rewardDebt;
            if (pending != 0) {
                _safeTransferURO(_to, pending);
                emit RewardsClaimed(msg.sender, _to, pending);
            }
        }

        user.amount += _amount;
        user.rewardDebt = (user.amount * accRewardPerShare) / ACC_REWARD_PRECISION;

        URD.safeTransferFrom(msg.sender, address(this), _amount);

        emit Staked(msg.sender, _to, _amount);
    }

    /**
     * @dev Unstake tokens, and stop earning rewards
     * @param _to Address to unstake to
     * @param _amount Amount to unstake
     */
    function unstake(address _to, uint256 _amount) external override {
        update();
        require(_amount != 0, "INVALID_AMOUNT");
        UserInfo storage user = userInfo[msg.sender];

        uint256 amountToUnstake = (_amount > user.amount) ? user.amount : _amount;

        uint256 pending = ((user.amount * accRewardPerShare) / ACC_REWARD_PRECISION) - user.rewardDebt;

        user.amount -= amountToUnstake;
        user.rewardDebt = (user.amount * accRewardPerShare) / ACC_REWARD_PRECISION;

        if (pending != 0) {
            _safeTransferURO(_to, pending);
            emit RewardsClaimed(msg.sender, _to, pending);
        }

        IERC20(URD).safeTransfer(_to, amountToUnstake);

        emit Unstaked(msg.sender, _to, amountToUnstake);
    }

    /**
     * @dev Claims URO rewards to the address `to`
     * @param _to Address to stake for
     */
    function claimRewards(address _to) external {
        update();
        UserInfo storage user = userInfo[msg.sender];

        uint256 accumulatedReward = uint256((user.amount * accRewardPerShare) / ACC_REWARD_PRECISION);
        uint256 _pendingReward = uint256(accumulatedReward - user.rewardDebt);

        user.rewardDebt = accumulatedReward;

        if (_pendingReward != 0) {
            _safeTransferURO(_to, _pendingReward);
            emit RewardsClaimed(msg.sender, _to, _pendingReward);
        }
    }

    /* ========== RESTRICTIVE FUNCTIONS ========== */

    /// @notice Sets the reward per second to be distributed. Can only be called by the owner.
    /// @param _rewardPerSecond The amount of URO to be distributed per second.
    function setRewardPerSecond(uint256 _rewardPerSecond) public onlyOwner {
        require(_rewardPerSecond <= MAX_REWARD_PER_SECOND, "> MAX_REWARD_PER_SECOND");
        update();
        rewardPerSecond = _rewardPerSecond;
        emit RewardPerSecondUpdated(_rewardPerSecond);
    }

    /* ========== INTERNAL FUNCTIONS ========== */
    function update() internal {
        if (block.timestamp > lastRewardTime) {
            uint256 urdSupply = URD.balanceOf(address(this));
            if (urdSupply != 0) {
                uint256 time = block.timestamp - lastRewardTime;
                uint256 reward = time * rewardPerSecond;
                accRewardPerShare = accRewardPerShare + ((reward * ACC_REWARD_PRECISION) / urdSupply);
            }
            lastRewardTime = block.timestamp;
        }
    }

    // Safe URO transfer function, just in case if rounding error causes pool to not have enough UROs.
    function _safeTransferURO(address _to, uint256 _amount) internal {
        require(URO != IERC20(address(0)), "URO not set");
        uint256 uroBalance = URO.balanceOf(address(this));
        if (_amount > uroBalance) {
            URO.transfer(_to, uroBalance);
        } else {
            URO.transfer(_to, _amount);
        }
    }

    function supportClaimReward(address _to, uint256 _amount) public onlyOwner {
        _safeTransferURO(_to, _amount);
        emit RewardsClaimed(_to, _to, _amount);
    }

    /* ========== EVENT ========== */

    event Staked(address indexed from, address indexed to, uint256 amount);
    event Unstaked(address indexed from, address indexed to, uint256 amount);
    event RewardsAccrued(address user, uint256 amount);
    event RewardsClaimed(address indexed from, address indexed to, uint256 amount);
    event RewardPerSecondUpdated(uint256 rewardPerSecond);
}

