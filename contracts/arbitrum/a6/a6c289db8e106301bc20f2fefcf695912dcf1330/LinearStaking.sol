//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.18;

import {ILinearStaking} from "./ILinearStaking.sol";
import {IAccessControlHolder} from "./IAccessControlHolder.sol";
import {ToInitialize} from "./ToInitialize.sol";
import {WithFees} from "./WithFees.sol";
import {ZeroAmountGuard} from "./ZeroAmountGuard.sol";
import {ZeroAddressGuard} from "./ZeroAddressGuard.sol";

import {IERC20} from "./IERC20.sol";
import {Ownable} from "./Ownable.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {IAccessControl} from "./IAccessControl.sol";

contract LinearStaking is
    ILinearStaking,
    ToInitialize,
    Ownable,
    WithFees,
    ZeroAmountGuard,
    ZeroAddressGuard
{
    using SafeERC20 for IERC20;

    uint256 constant UNLOCK_TIMESTAMP_MINIMUM_DIFF = 30 days;

    IERC20 public immutable override stakingToken;
    IERC20 public immutable override rewardToken;

    uint256 public override totalSupply;
    uint256 public start;
    uint256 public override duration;
    uint256 public updatedAt;
    uint256 public rewardRate;
    uint256 public rewardPerTokenStored;
    uint256 public unlockTokensTimestamp;
    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;
    mapping(address => uint256) public override balanceOf;

    modifier updateReward(address _account) {
        rewardPerTokenStored = rewardPerToken();
        updatedAt = lastTimeRewardApplicable();

        if (_account != address(0)) {
            rewards[_account] = earned(_account);
            userRewardPerTokenPaid[_account] = rewardPerTokenStored;
        }

        _;
    }

    modifier isOngoing() {
        if (block.timestamp < start) {
            revert BeforeStakingStart();
        }
        if (finishAt() < block.timestamp) {
            revert AfterStakingFinish();
        }
        _;
    }

    constructor(
        IERC20 stakingToken_,
        IERC20 rewardToken_,
        IAccessControl acl_,
        address treasury_,
        uint256 fees_
    ) Ownable() WithFees(acl_, treasury_, fees_) {
        stakingToken = stakingToken_;
        rewardToken = rewardToken_;
    }

    function initialize(
        uint256 amount_,
        uint256 duration_,
        uint256 start_,
        uint256 unlockTokensTimestamp_
    )
        external
        notInitialized
        onlyOwner
        notZeroAmount(amount_)
        notZeroAmount(duration_)
    {
        if (rewardToken.balanceOf(address(this)) < amount_) {
            revert RewardBalanceTooSmall();
        }

        if (block.timestamp > start_) {
            revert StartNotValid();
        }

        duration = duration_;
        rewardRate = amount_ / duration_;
        start = start_;
        updatedAt = block.timestamp;
        unlockTokensTimestamp = unlockTokensTimestamp_;

        if (
            finishAt() + UNLOCK_TIMESTAMP_MINIMUM_DIFF > unlockTokensTimestamp_
        ) {
            revert NotValidUnlockTimestamp();
        }

        initialized = true;

        emit Initialized(start_, duration_, amount_, unlockTokensTimestamp_);
    }

    function unlockTokens(
        IERC20 token,
        address to,
        uint256 amount
    )
        external
        notZeroAmount(amount)
        notZeroAddress(to)
        isInitialized
        onlyOwner
    {
        if (block.timestamp < unlockTokensTimestamp) {
            revert ToEarlyToWithdrawReward();
        }

        token.safeTransfer(to, amount);
    }

    function stake(
        uint256 amount
    ) external override isInitialized isOngoing updateReward(msg.sender) {
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        balanceOf[msg.sender] += amount;
        totalSupply += amount;

        emit Staked(msg.sender, amount);
    }

    function withdraw(
        uint256 amount
    )
        external
        payable
        override
        onlyWithFees
        isInitialized
        notZeroAmount(amount)
        updateReward(msg.sender)
    {
        stakingToken.safeTransfer(msg.sender, amount);
        balanceOf[msg.sender] -= amount;
        totalSupply -= amount;

        emit Unstaked(msg.sender, amount);
    }

    function getReward()
        external
        payable
        virtual
        isInitialized
        onlyWithFees
        updateReward(msg.sender)
    {
        uint256 reward = rewards[msg.sender];
        if (reward == 0) {
            revert AmountZero();
        }

        rewards[msg.sender] = 0;
        rewardToken.safeTransfer(msg.sender, reward);

        emit RewardTaken(msg.sender, reward);
    }

    function rewardPerToken() public view override returns (uint) {
        if (totalSupply == 0 || block.timestamp < start) {
            return rewardPerTokenStored;
        }

        return
            rewardPerTokenStored +
            (rewardRate * (lastTimeRewardApplicable() - updatedAt) * 1e18) /
            totalSupply;
    }

    function earned(address _account) public view override returns (uint256) {
        return
            ((balanceOf[_account] *
                ((rewardPerToken() - userRewardPerTokenPaid[_account]))) /
                1e18) + rewards[_account];
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
        return _min(finishAt(), block.timestamp);
    }

    function finishAt() public view override returns (uint256) {
        return start + duration;
    }

    function _min(uint x, uint y) private pure returns (uint256) {
        return x <= y ? x : y;
    }
}

