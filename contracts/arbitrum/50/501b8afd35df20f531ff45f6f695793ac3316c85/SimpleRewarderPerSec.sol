// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {Ownable2StepUpgradeable} from "./Ownable2StepUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "./ReentrancyGuardUpgradeable.sol";

import {Clone} from "./Clone.sol";

import {IAPTFarm} from "./IAPTFarm.sol";
import {IWrappedNative} from "./IWrappedNative.sol";
import {ISimpleRewarderPerSec} from "./ISimpleRewarderPerSec.sol";

/**
 * This is a sample contract to be used in the APTFarm contract for partners to reward
 * stakers with their native token alongside JOE.
 *
 * It assumes no minting rights, so requires a set amount of YOUR_TOKEN to be transferred to this contract prior.
 * E.g. say you've allocated 100,000 XYZ to the JOE-XYZ farm over 30 days. Then you would need to transfer
 * 100,000 XYZ and set the reward per sec accordingly so it's fully distributed after 30 days.
 *
 *
 * Issue with the previous version is that this fraction, `tokenReward*(ACC_TOKEN_PRECISION)/(aptSupply)`,
 * can return 0 or be very inacurate with some tokens:
 *      uint256 timeElapsed = block.timestamp-(farm.lastRewardTimestamp);
 *      uint256 tokenReward = timeElapsed*(tokenPerSec);
 *      accTokenPerShare = accTokenPerShare+(
 *          tokenReward*(ACC_TOKEN_PRECISION)/(aptSupply)
 *      );
 *  The goal is to set ACC_TOKEN_PRECISION high enough to prevent this without causing overflow too.
 */
contract SimpleRewarderPerSec is Ownable2StepUpgradeable, ReentrancyGuardUpgradeable, Clone, ISimpleRewarderPerSec {
    using SafeERC20 for IERC20;

    uint256 public override tokenPerSec;

    /**
     * Given the fraction, tokenReward * ACC_TOKEN_PRECISION / aptSupply, we consider
     * several edge cases.
     *
     * Edge case n1: maximize the numerator, minimize the denominator.
     * `aptSupply` = 1 WEI
     * `tokenPerSec` = 1e(30)
     * `timeElapsed` = 31 years, i.e. 1e9 seconds
     * result = 1e9 * 1e30 * 1e36 / 1
     *        = 1e75
     * (No overflow as max uint256 is 1.15e77).
     * PS: This will overflow when `timeElapsed` becomes greater than 1e11, i.e. in more than 3_000 years
     * so it should be fine.
     *
     * Edge case n2: minimize the numerator, maximize the denominator.
     * `aptSupply` = max(uint112) = 1e34
     * `tokenPerSec` = 1 WEI
     * `timeElapsed` = 1 second
     * result = 1 * 1 * 1e36 / 1e34
     *        = 1e2
     * (Not rounded to zero, therefore ACC_TOKEN_PRECISION = 1e36 is safe)
     */
    uint256 private constant ACC_TOKEN_PRECISION = 1e36;

    /**
     * @notice Info of the farmInfo.
     */
    FarmInfo public farmInfo;

    /**
     * @notice Info of each user that stakes LP tokens.
     */
    mapping(address => UserInfo) public userInfo;

    modifier onlyAPTFarm() {
        if (msg.sender != address(_aptFarm())) {
            revert SimpleRewarderPerSec__OnlyAPTFarm();
        }
        _;
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(uint256 _tokenPerSec, address _owner) external initializer {
        if (_tokenPerSec > 1e30) {
            revert SimpleRewarderPerSec__InvalidTokenPerSec();
        }

        __Ownable2Step_init();
        __ReentrancyGuard_init();

        tokenPerSec = _tokenPerSec;
        farmInfo = FarmInfo({lastRewardTimestamp: block.timestamp, accTokenPerShare: 0});

        _transferOwnership(_owner);
    }

    /**
     * @notice Reward token.
     */
    function rewardToken() external pure override returns (IERC20) {
        return _rewardToken();
    }

    /**
     * @notice Corresponding APT token of this rewarder.
     */
    function apToken() external pure override returns (IERC20) {
        return _apToken();
    }

    /**
     * @notice APT farm contract.
     */
    function aptFarm() external pure override returns (IAPTFarm) {
        return _aptFarm();
    }

    /**
     * @notice Wrapped native token.
     */
    function wNative() external pure override returns (IWrappedNative) {
        return _wNative();
    }

    /**
     * @notice Returns true if the reward token is the native currency.
     */
    function isNative() external pure override returns (bool) {
        return _isNative();
    }

    /**
     * @dev Receive function. Mainly added to silence the compiler warning.
     * Highly unlikely to be used as the rewarder needs at least 61 bytes of immutable data added to the payload
     * (3 addresses and 1 bytes), so this function should never be called.
     */
    receive() external payable {}

    /**
     * @notice Allows the contract to receive native tokens.
     * @dev We can't use the `receive` function because the immutable clone library adds calldata to the payload
     * that are taken as a function signature and parameters.
     */
    fallback() external payable {}

    /**
     * @notice Function called by MasterChefJoe whenever staker claims JOE harvest. Allows staker to also receive a 2nd reward token.
     * @param _user Address of user
     * @param _aptAmount Number of LP tokens the user has
     */
    function onJoeReward(address _user, uint256 _aptAmount, uint256 aptSupply)
        external
        override
        onlyAPTFarm
        nonReentrant
    {
        FarmInfo memory farm = _updateFarm(aptSupply);
        UserInfo storage user = userInfo[_user];

        uint256 previousUserAmount = user.amount;
        uint256 previousUserRewardDebt = user.rewardDebt;

        user.amount = _aptAmount;
        user.rewardDebt = (_aptAmount * farm.accTokenPerShare) / ACC_TOKEN_PRECISION;

        uint256 pending;
        if (previousUserAmount > 0) {
            pending = (previousUserAmount * farm.accTokenPerShare) / ACC_TOKEN_PRECISION - previousUserRewardDebt
                + user.unpaidRewards;

            uint256 rewardBalance = _balance();
            if (_isNative()) {
                if (pending > rewardBalance) {
                    user.unpaidRewards = pending - rewardBalance;
                    _transferNative(_user, rewardBalance);
                } else {
                    user.unpaidRewards = 0;
                    _transferNative(_user, pending);
                }
            } else {
                if (pending > rewardBalance) {
                    user.unpaidRewards = pending - rewardBalance;
                    _rewardToken().safeTransfer(_user, rewardBalance);
                } else {
                    user.unpaidRewards = 0;
                    _rewardToken().safeTransfer(_user, pending);
                }
            }
        }

        emit OnReward(_user, pending - user.unpaidRewards);
    }

    /**
     * @notice Update reward variables of the given farmInfo.
     * @return farm Returns the farm that was updated.
     */
    function updateFarm() external returns (FarmInfo memory farm) {
        farm = _updateFarm(_aptFarm().apTokenBalances(_apToken()));
    }

    /**
     * @notice View function to see pending tokens
     * @param _user Address of user.
     * @return pending reward for a given user.
     */
    function pendingTokens(address _user) external view override returns (uint256 pending) {
        FarmInfo memory farm = farmInfo;
        UserInfo storage user = userInfo[_user];

        uint256 accTokenPerShare = farm.accTokenPerShare;
        uint256 aptSupply = _apToken().balanceOf(address(_aptFarm()));

        if (block.timestamp > farm.lastRewardTimestamp && aptSupply != 0) {
            uint256 timeElapsed = block.timestamp - farm.lastRewardTimestamp;
            uint256 tokenReward = timeElapsed * tokenPerSec;
            accTokenPerShare = accTokenPerShare + (tokenReward * ACC_TOKEN_PRECISION) / aptSupply;
        }

        pending = (user.amount * accTokenPerShare) / ACC_TOKEN_PRECISION - user.rewardDebt + user.unpaidRewards;
    }

    /**
     * @notice View function to see balance of reward token.
     */
    function balance() external view returns (uint256) {
        return _balance();
    }

    /**
     * @notice Sets the distribution reward rate. This will also update the farmInfo.
     * @param _tokenPerSec The number of tokens to distribute per second
     */
    function setRewardRate(uint256 _tokenPerSec) external onlyOwner {
        if (_tokenPerSec > 1e30) {
            revert SimpleRewarderPerSec__InvalidTokenPerSec();
        }

        _updateFarm(_aptFarm().apTokenBalances(_apToken()));

        uint256 oldRate = tokenPerSec;
        tokenPerSec = _tokenPerSec;

        emit RewardRateUpdated(oldRate, _tokenPerSec);
    }

    /**
     * @notice In case rewarder is stopped before emissions finished, this function allows
     * withdrawal of remaining tokens.
     * @param token Address of token to withdraw
     */
    function emergencyWithdraw(address token) external onlyOwner {
        if (token == address(0)) {
            _transferNative(msg.sender, address(this).balance);
        } else {
            IERC20(token).safeTransfer(address(msg.sender), IERC20(token).balanceOf(address(this)));
        }
    }

    function _updateFarm(uint256 aptSupply) internal returns (FarmInfo memory farm) {
        farm = farmInfo;

        if (block.timestamp > farm.lastRewardTimestamp) {
            if (aptSupply > 0) {
                uint256 timeElapsed = block.timestamp - farm.lastRewardTimestamp;
                uint256 tokenReward = timeElapsed * tokenPerSec;
                farm.accTokenPerShare = farm.accTokenPerShare + (tokenReward * ACC_TOKEN_PRECISION) / aptSupply;
            }

            farm.lastRewardTimestamp = block.timestamp;
            farmInfo = farm;
        }
    }

    function _balance() internal view returns (uint256) {
        if (_isNative()) {
            return address(this).balance;
        } else {
            return _rewardToken().balanceOf(address(this));
        }
    }

    /**
     * @dev Sends native tokens to recipient.
     * @dev Native rewards will be wrapped into wNative if the staker can't receive native tokens.
     * @param to Recipient of the transfer
     * @param amount Amount to transfer
     */
    function _transferNative(address to, uint256 amount) internal {
        (bool success,) = to.call{value: amount}("");
        if (!success) {
            _wNative().deposit{value: amount}();
            IERC20(_wNative()).safeTransfer(to, amount);
        }
    }

    /**
     * @dev Returns the address of the reward token.
     * @return Address of the reward token
     */
    function _rewardToken() internal pure returns (IERC20) {
        return IERC20(_getArgAddress(0));
    }

    /**
     * @dev Returns the address of the wrapped native token.
     * @return Address of the wrapped native token
     */
    function _apToken() internal pure returns (IERC20) {
        return IERC20(_getArgAddress(20));
    }

    /**
     * @dev Returns the address of the APT Farm.
     * @return Address of the APT Farm
     */
    function _aptFarm() internal pure returns (IAPTFarm) {
        return IAPTFarm(_getArgAddress(40));
    }

    /**
     * @dev Returns the address of the wrapped native token.
     * @return Address of the wrapped native token
     */
    function _wNative() internal pure returns (IWrappedNative) {
        return IWrappedNative(_getArgAddress(60));
    }

    /**
     * @dev Returns true if the reward token is native.
     * @return True if the reward token is native
     */
    function _isNative() internal pure returns (bool) {
        return _getArgUint8(80) > 0;
    }
}

