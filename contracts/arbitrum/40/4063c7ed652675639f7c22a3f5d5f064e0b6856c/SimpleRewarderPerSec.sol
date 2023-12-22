// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;
pragma experimental ABIEncoderV2;

import "./Address.sol";
import "./Math.sol";
import "./ReentrancyGuard.sol";
import "./Ownable.sol";

import "./SafeERC20.sol";
import "./IRewarder.sol";
import "./IMasterChefJoe.sol";

/**
 * This is a sample contract to be used in the MasterChefJoe contract for partners to reward
 * stakers with their native token alongside JOE.
 *
 * It assumes no minting rights, so requires a set amount of YOUR_TOKEN to be transferred to this contract prior.
 * E.g. say you've allocated 100,000 XYZ to the JOE-XYZ farm over 30 days. Then you would need to transfer
 * 100,000 XYZ and set the block reward accordingly so it's fully distributed after 30 days.
 *
 *
 * Issue with the previous version is that this fraction, `tokenReward.mul(ACC_TOKEN_PRECISION).div(lpSupply)`,
 * can return 0 or be very inacurate with some tokens:
 *      uint256 timeElapsed = block.timestamp.sub(pool.lastRewardTimestamp);
 *      uint256 tokenReward = timeElapsed.mul(tokenPerSec);
 *      accTokenPerShare = accTokenPerShare.add(
 *          tokenReward.mul(ACC_TOKEN_PRECISION).div(lpSupply)
 *      );
 *  The goal is to set ACC_TOKEN_PRECISION high enough to prevent this without causing overflow too.
 */
contract SimpleRewarderPerSec is IRewarder, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Info of each MCJ user.
    /// `amount` LP token amount the user has provided.
    /// `rewardDebt` The amount of YOUR_TOKEN entitled to the user.
    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
        uint256 unpaidRewards;
    }

    /// @notice Info of each MCJ poolInfo.
    /// `accTokenPerShare` Amount of YOUR_TOKEN each LP token is worth.
    /// `lastRewardTimestamp` The last timestamp YOUR_TOKEN was rewarded to the poolInfo.
    struct PoolInfo {
        uint256 accTokenPerShare;
        uint256 lastRewardTimestamp;
    }

    IERC20 public immutable override rewardToken;
    IERC20 public immutable lpToken;
    bool public immutable isNative;
    IMasterChefJoe public immutable MCJ;
    uint256 public tokenPerSec;

    // Given the fraction, tokenReward * ACC_TOKEN_PRECISION / lpSupply, we consider
    // several edge cases.
    //
    // Edge case n1: maximize the numerator, minimize the denominator.
    // `lpSupply` = 1 WEI
    // `tokenPerSec` = 1e(30)
    // `timeElapsed` = 31 years, i.e. 1e9 seconds
    // result = 1e9 * 1e30 * 1e36 / 1
    //        = 1e75
    // (No overflow as max uint256 is 1.15e77).
    // PS: This will overflow when `timeElapsed` becomes greater than 1e11, i.e. in more than 3_000 years
    // so it should be fine.
    //
    // Edge case n2: minimize the numerator, maximize the denominator.
    // `lpSupply` = max(uint112) = 1e34
    // `tokenPerSec` = 1 WEI
    // `timeElapsed` = 1 second
    // result = 1 * 1 * 1e36 / 1e34
    //        = 1e2
    // (Not rounded to zero, therefore ACC_TOKEN_PRECISION = 1e36 is safe)
    uint256 private constant ACC_TOKEN_PRECISION = 1e36;

    /// @notice Info of the poolInfo.
    PoolInfo public poolInfo;
    /// @notice Info of each user that stakes LP tokens.
    mapping(address => UserInfo) public userInfo;

    event OnReward(address indexed user, uint256 amount);
    event RewardRateUpdated(uint256 oldRate, uint256 newRate);

    modifier onlyMCJ() {
        require(msg.sender == address(MCJ), "onlyMCJ: only MasterChefJoe can call this function");
        _;
    }

    constructor(IERC20 _rewardToken, IERC20 _lpToken, uint256 _tokenPerSec, IMasterChefJoe _MCJ, bool _isNative) {
        require(Address.isContract(address(_rewardToken)), "constructor: reward token must be a valid contract");
        require(Address.isContract(address(_lpToken)), "constructor: LP token must be a valid contract");
        require(Address.isContract(address(_MCJ)), "constructor: MasterChefJoe must be a valid contract");
        require(_tokenPerSec <= 1e30, "constructor: token per seconds can't be greater than 1e30");

        rewardToken = _rewardToken;
        lpToken = _lpToken;
        tokenPerSec = _tokenPerSec;
        MCJ = _MCJ;
        isNative = _isNative;
        poolInfo = PoolInfo({lastRewardTimestamp: block.timestamp, accTokenPerShare: 0});
    }

    /// @notice payable function needed to receive AVAX
    receive() external payable {
        require(isNative, "Non native rewarder");
    }

    /// @notice Function called by MasterChefJoe whenever staker claims JOE harvest. Allows staker to also receive a 2nd reward token.
    /// @param _user Address of user
    /// @param _lpAmount Number of LP tokens the user has
    function onJoeReward(address _user, uint256 _lpAmount) external override onlyMCJ nonReentrant {
        updatePool();

        uint256 accTokenPerShare = poolInfo.accTokenPerShare;
        UserInfo storage user = userInfo[_user];

        uint256 pending = user.unpaidRewards;
        uint256 userAmount = user.amount;

        if (userAmount > 0 || pending > 0) {
            pending = (userAmount * (accTokenPerShare) / ACC_TOKEN_PRECISION) - (user.rewardDebt) + (pending);

            if (pending > 0) {
                uint256 _balance;
                if (isNative) {
                    _balance = address(this).balance;

                    if (_balance > 0) {
                        if (pending > _balance) {
                            (bool success) = true; //_user.call.value(balance)("");
                            require(success, "Transfer failed");
                            user.unpaidRewards = pending - _balance;
                        } else {
                            (bool success) = true; //_user.call.value(pending)("");
                            require(success, "Transfer failed");
                            user.unpaidRewards = 0;
                        }
                    }
                } else {
                    _balance = rewardToken.balanceOf(address(this));

                    if (_balance > 0) {
                        if (pending > _balance) {
                            rewardToken.safeTransfer(_user, _balance);
                            user.unpaidRewards = pending - _balance;
                        } else {
                            rewardToken.safeTransfer(_user, pending);
                            user.unpaidRewards = 0;
                        }
                    }
                }
            }
        }

        user.amount = _lpAmount;
        user.rewardDebt = _lpAmount * (accTokenPerShare) / ACC_TOKEN_PRECISION;
        emit OnReward(_user, pending - user.unpaidRewards);
    }

    /// @notice View function to see pending tokens
    /// @param _user Address of user.
    /// @return pending reward for a given user.
    function pendingTokens(address _user) external view override returns (uint256 pending) {
        PoolInfo memory pool = poolInfo;
        UserInfo storage user = userInfo[_user];

        uint256 accTokenPerShare = pool.accTokenPerShare;
        uint256 lpSupply = lpToken.balanceOf(address(MCJ));

        if (block.timestamp > pool.lastRewardTimestamp && lpSupply != 0) {
            uint256 timeElapsed = block.timestamp - (pool.lastRewardTimestamp);
            uint256 tokenReward = timeElapsed * (tokenPerSec);
            accTokenPerShare = accTokenPerShare + (tokenReward * (ACC_TOKEN_PRECISION) / (lpSupply));
        }

        pending = (user.amount * (accTokenPerShare) / ACC_TOKEN_PRECISION) - (user.rewardDebt) + (user.unpaidRewards);
    }

    /// @notice View function to see balance of reward token.
    function balance() external view returns (uint256) {
        if (isNative) {
            return address(this).balance;
        } else {
            return rewardToken.balanceOf(address(this));
        }
    }

    /// @notice Sets the distribution reward rate. This will also update the poolInfo.
    /// @param _tokenPerSec The number of tokens to distribute per second
    function setRewardRate(uint256 _tokenPerSec) external onlyOwner {
        updatePool();

        uint256 oldRate = tokenPerSec;
        tokenPerSec = _tokenPerSec;

        emit RewardRateUpdated(oldRate, _tokenPerSec);
    }

    /// @notice Update reward variables of the given poolInfo.
    /// @return pool Returns the pool that was updated.
    function updatePool() public returns (PoolInfo memory pool) {
        pool = poolInfo;

        if (block.timestamp > pool.lastRewardTimestamp) {
            uint256 lpSupply = lpToken.balanceOf(address(MCJ));

            if (lpSupply > 0) {
                uint256 timeElapsed = block.timestamp - (pool.lastRewardTimestamp);
                uint256 tokenReward = timeElapsed * (tokenPerSec);
                pool.accTokenPerShare = pool.accTokenPerShare + ((tokenReward * (ACC_TOKEN_PRECISION) / lpSupply));
            }

            pool.lastRewardTimestamp = block.timestamp;
            poolInfo = pool;
        }
    }

    /// @notice In case rewarder is stopped before emissions finished, this function allows
    /// withdrawal of remaining tokens.
    function emergencyWithdraw() public onlyOwner {
        if (isNative) {
            (bool success) = true; //msg.sender.call.value{address(this).balance}("");
            require(success, "Transfer failed");
        } else {
            rewardToken.safeTransfer(address(msg.sender), rewardToken.balanceOf(address(this)));
        }
    }
}

