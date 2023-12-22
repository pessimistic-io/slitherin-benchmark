// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import {Ownable2Step} from "./Ownable2Step.sol";
import {EnumerableMap} from "./EnumerableMap.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";
import {IERC20, IERC20Metadata} from "./IERC20Metadata.sol";
import {SafeERC20} from "./SafeERC20.sol";

import {IAPTFarm, IRewarder} from "./IAPTFarm.sol";

/**
 * @notice Unlike MasterChefJoeV3, the APTFarm contract gives out a set number of joe tokens per seconds to every farm configured
 * These Joe tokens needs to be deposited on the contract first.
 */
contract APTFarm is Ownable2Step, ReentrancyGuard, IAPTFarm {
    using EnumerableMap for EnumerableMap.AddressToUintMap;
    using SafeERC20 for IERC20;

    uint256 private constant ACC_TOKEN_PRECISION = 1e36;

    uint256 private constant MAX_JOE_PER_SEC = 100e18;

    /**
     * @notice Whether if the given token already has a farm or not.
     */
    EnumerableMap.AddressToUintMap private _vaultsWithFarms;

    /**
     * @dev Info of each individual farm.
     */
    FarmInfo[] private _farmInfo;

    /**
     * @dev Info of each user that stakes APT tokens.
     */
    mapping(uint256 => mapping(address => UserInfo)) private _userInfo;

    /**
     * @notice Address of the joe token.
     */
    IERC20 public immutable override joe;

    /**
     * @notice Accounted balances of AP tokens in the farm.
     */
    mapping(IERC20 => uint256) public override apTokenBalances;

    /**
     * @dev joePerSec is limited to 100 tokens per second to avoid overflow issues
     * @param joePerSec The amount of joe tokens that will be given per second.
     */
    modifier validateJoePerSec(uint256 joePerSec) {
        if (joePerSec > MAX_JOE_PER_SEC) {
            revert APTFarm__InvalidJoePerSec();
        }
        _;
    }

    /**
     * @dev Checks if the given amount is not zero.
     * @param amount The amount to validate.
     */
    modifier nonZeroAmount(uint256 amount) {
        if (amount == 0) {
            revert APTFarm__ZeroAmount();
        }
        _;
    }

    /**
     * @dev Checks if the given array is not empty.
     * @param array The uint256 array to validate.
     */
    modifier validateArrayLength(uint256[] calldata array) {
        if (array.length == 0) {
            revert APTFarm__EmptyArray();
        }
        _;
    }

    /**
     * @param _joe The joe token contract address.
     */
    constructor(IERC20 _joe) {
        if (address(_joe) == address(0)) {
            revert APTFarm__ZeroAddress();
        }

        joe = _joe;
    }

    /**
     * @notice Returns the number of APTFarm farms.
     */
    function farmLength() external view override returns (uint256 farms) {
        farms = _farmInfo.length;
    }

    /**
     * @notice Returns true if the given APT token has a farm.
     * @param apToken Address of the APT ERC-20 token.
     */
    function hasFarm(address apToken) external view override returns (bool) {
        return _vaultsWithFarms.contains(apToken);
    }

    /**
     * @notice Returns the farm id of the given APT token.
     * @param apToken Address of the APT ERC-20 token.
     */
    function vaultFarmId(address apToken) external view override returns (uint256) {
        return _vaultsWithFarms.get(apToken);
    }

    /**
     * @notice Returns informations about the farm at the given index.
     * @param index The index of the farm.
     * @return farm The farm informations.
     */
    function farmInfo(uint256 index) external view override returns (FarmInfo memory farm) {
        farm = _farmInfo[index];
    }

    /**
     * @notice Returns informations about the user in the given farm.
     * @param index The index of the farm.
     * @param user The address of the user.
     * @return info The user informations.
     */
    function userInfo(uint256 index, address user) external view override returns (UserInfo memory info) {
        info = _userInfo[index][user];
    }

    /**
     * @notice Add a new APT to the farm set. Can only be called by the owner.
     * @param joePerSec Initial number of joe tokens per second streamed to the farm.
     * @param apToken Address of the APT ERC-20 token.
     * @param rewarder Address of the rewarder delegate.
     */
    function add(uint256 joePerSec, IERC20 apToken, IRewarder rewarder)
        external
        override
        onlyOwner
        validateJoePerSec(joePerSec)
    {
        if (address(apToken) == address(joe)) {
            revert APTFarm__InvalidAPToken();
        }

        uint256 newPid = _farmInfo.length;

        if (!_vaultsWithFarms.set(address(apToken), newPid)) {
            revert APTFarm__TokenAlreadyHasFarm(address(apToken));
        }

        _farmInfo.push(
            FarmInfo({
                apToken: apToken,
                lastRewardTimestamp: block.timestamp,
                accJoePerShare: 0,
                joePerSec: joePerSec,
                rewarder: rewarder
            })
        );

        // Sanity check to ensure apToken is an ERC20 token
        apToken.balanceOf(address(this));

        // Sanity check if we add a rewarder
        if (address(rewarder) != address(0)) {
            rewarder.onJoeReward(address(0), 0, 0);
        }

        emit Add(newPid, joePerSec, apToken, rewarder);
    }

    /**
     * @notice Update the given farm's joe allocation point and `IRewarder` contract. Can only be called by the owner.
     * @param pid The index of the farm. See `_farmInfo`.
     * @param joePerSec New joe per sec streamed to the farm.
     * @param rewarder Address of the rewarder delegate.
     * @param overwrite True if _rewarder should be `set`. Otherwise `_rewarder` is ignored.
     */
    function set(uint256 pid, uint256 joePerSec, IRewarder rewarder, bool overwrite)
        external
        override
        onlyOwner
        validateJoePerSec(joePerSec)
    {
        FarmInfo memory farm = _updateFarm(pid);
        farm.joePerSec = joePerSec;

        if (overwrite) {
            farm.rewarder = rewarder;
            rewarder.onJoeReward(address(0), 0, apTokenBalances[farm.apToken]); // sanity check
        }

        _farmInfo[pid] = farm;

        emit Set(pid, joePerSec, overwrite ? rewarder : farm.rewarder, overwrite);
    }

    /**
     * @notice View function to see pending joe on frontend.
     * @param pid The index of the farm. See `_farmInfo`.
     * @param user Address of user.
     * @return pendingJoe joe reward for a given user.
     * @return bonusTokenAddress The address of the bonus reward.
     * @return bonusTokenSymbol The symbol of the bonus token.
     * @return pendingBonusToken The amount of bonus rewards pending.
     */
    function pendingTokens(uint256 pid, address user)
        external
        view
        override
        returns (
            uint256 pendingJoe,
            address bonusTokenAddress,
            string memory bonusTokenSymbol,
            uint256 pendingBonusToken
        )
    {
        FarmInfo memory farm = _farmInfo[pid];
        UserInfo storage userInfoCached = _userInfo[pid][user];

        if (block.timestamp > farm.lastRewardTimestamp) {
            uint256 apTokenSupply = apTokenBalances[farm.apToken];
            _refreshFarmState(farm, apTokenSupply);
        }

        pendingJoe = (userInfoCached.amount * farm.accJoePerShare) / ACC_TOKEN_PRECISION - userInfoCached.rewardDebt
            + userInfoCached.unpaidRewards;

        // If it's a double reward farm, we return info about the bonus token
        IRewarder rewarder = farm.rewarder;
        if (address(rewarder) != address(0)) {
            bonusTokenAddress = address(rewarder.rewardToken());

            (bool success, bytes memory data) =
                bonusTokenAddress.staticcall(abi.encodeWithSelector(IERC20Metadata.symbol.selector));

            if (success && data.length > 0) {
                bonusTokenSymbol = abi.decode(data, (string));
            }

            pendingBonusToken = rewarder.pendingTokens(user);
        }
    }

    /**
     * @notice Deposit APT tokens to the APTFarm for joe allocation.
     * @param pid The index of the farm. See `_farmInfo`.
     * @param amount APT token amount to deposit.
     */
    function deposit(uint256 pid, uint256 amount) external override nonReentrant nonZeroAmount(amount) {
        FarmInfo memory farm = _updateFarm(pid);
        UserInfo storage user = _userInfo[pid][msg.sender];

        (uint256 userAmountBefore, uint256 userRewardDebt, uint256 userUnpaidRewards) =
            (user.amount, user.rewardDebt, user.unpaidRewards);

        uint256 balanceBefore = farm.apToken.balanceOf(address(this));
        farm.apToken.safeTransferFrom(msg.sender, address(this), amount);
        uint256 receivedAmount = farm.apToken.balanceOf(address(this)) - balanceBefore;

        uint256 userAmount = userAmountBefore + receivedAmount;
        uint256 apTokenBalanceBefore = apTokenBalances[farm.apToken];

        user.rewardDebt = (userAmount * farm.accJoePerShare) / ACC_TOKEN_PRECISION;
        user.amount = userAmount;
        apTokenBalances[farm.apToken] = apTokenBalanceBefore + receivedAmount;

        if (userAmountBefore > 0 || userUnpaidRewards > 0) {
            user.unpaidRewards = _harvest(userAmountBefore, userRewardDebt, userUnpaidRewards, pid, farm.accJoePerShare);
        }

        IRewarder _rewarder = farm.rewarder;
        if (address(_rewarder) != address(0)) {
            _rewarder.onJoeReward(msg.sender, userAmount, apTokenBalanceBefore);
        }

        emit Deposit(msg.sender, pid, receivedAmount);
    }

    /**
     * @notice Withdraw APT tokens from the APTFarm.
     * @param pid The index of the farm. See `_farmInfo`.
     * @param amount APT token amount to withdraw.
     */
    function withdraw(uint256 pid, uint256 amount) external override nonReentrant nonZeroAmount(amount) {
        FarmInfo memory farm = _updateFarm(pid);
        UserInfo storage user = _userInfo[pid][msg.sender];

        (uint256 userAmountBefore, uint256 userRewardDebt, uint256 userUnpaidRewards) =
            (user.amount, user.rewardDebt, user.unpaidRewards);

        if (userAmountBefore < amount) {
            revert APTFarm__InsufficientDeposit(userAmountBefore, amount);
        }

        uint256 userAmount = userAmountBefore - amount;
        uint256 apTokenBalanceBefore = apTokenBalances[farm.apToken];

        user.rewardDebt = (userAmount * farm.accJoePerShare) / ACC_TOKEN_PRECISION;
        user.amount = userAmount;
        apTokenBalances[farm.apToken] = apTokenBalanceBefore - amount;

        if (userAmountBefore > 0 || userUnpaidRewards > 0) {
            user.unpaidRewards = _harvest(userAmountBefore, userRewardDebt, userUnpaidRewards, pid, farm.accJoePerShare);
        }

        IRewarder _rewarder = farm.rewarder;
        if (address(_rewarder) != address(0)) {
            _rewarder.onJoeReward(msg.sender, userAmount, apTokenBalanceBefore);
        }

        farm.apToken.safeTransfer(msg.sender, amount);

        emit Withdraw(msg.sender, pid, amount);
    }

    /**
     * @notice Withdraw without caring about rewards. EMERGENCY ONLY.
     * @param pid The index of the farm. See `_farmInfo`.
     */
    function emergencyWithdraw(uint256 pid) external override nonReentrant {
        FarmInfo memory farm = _farmInfo[pid];
        UserInfo storage user = _userInfo[pid][msg.sender];

        uint256 amount = user.amount;
        uint256 apTokenBalanceBefore = apTokenBalances[farm.apToken];

        user.amount = 0;
        user.rewardDebt = 0;
        apTokenBalances[farm.apToken] = apTokenBalanceBefore - amount;

        IRewarder _rewarder = farm.rewarder;
        if (address(_rewarder) != address(0)) {
            _rewarder.onJoeReward(msg.sender, 0, apTokenBalanceBefore);
        }

        // Note: transfer can fail or succeed if `amount` is zero.
        farm.apToken.safeTransfer(msg.sender, amount);
        emit EmergencyWithdraw(msg.sender, pid, amount);
    }

    /**
     * @notice Harvest rewards from the APTFarm for all the given farms.
     * @param pids The indices of the farms to harvest from.
     */
    function harvestRewards(uint256[] calldata pids) external override nonReentrant validateArrayLength(pids) {
        uint256 length = pids.length;
        for (uint256 i = 0; i < length; i++) {
            uint256 pid = pids[i];

            FarmInfo memory farm = _updateFarm(pid);
            UserInfo storage user = _userInfo[pid][msg.sender];

            (uint256 userAmount, uint256 userRewardDebt, uint256 userUnpaidRewards) =
                (user.amount, user.rewardDebt, user.unpaidRewards);

            user.rewardDebt = (userAmount * farm.accJoePerShare) / ACC_TOKEN_PRECISION;

            if (userAmount > 0 || userUnpaidRewards > 0) {
                user.unpaidRewards = _harvest(userAmount, userRewardDebt, userUnpaidRewards, pid, farm.accJoePerShare);
            }

            IRewarder rewarder = farm.rewarder;
            if (address(rewarder) != address(0)) {
                rewarder.onJoeReward(msg.sender, userAmount, apTokenBalances[farm.apToken]);
            }
        }

        emit BatchHarvest(msg.sender, pids);
    }

    /**
     * @notice Allows owner to withdraw any tokens that have been sent to the APTFarm by mistake.
     * @param token The address of the AP token to skim.
     * @param to The address to send the AP token to.
     */
    function skim(IERC20 token, address to) external override onlyOwner {
        uint256 contractBalance = token.balanceOf(address(this));
        uint256 totalDeposits = apTokenBalances[token];

        if (contractBalance > totalDeposits) {
            uint256 amount = contractBalance - totalDeposits;
            token.safeTransfer(to, amount);
            emit Skim(address(token), to, amount);
        }
    }

    /**
     * @dev Get the new farm state if time passed since last update.
     * @dev View function that needs to be commited if effectively updating the farm.
     * @param farm The farm to update.
     * @param apTokenSupply The total amount of APT tokens in the farm.
     */
    function _refreshFarmState(FarmInfo memory farm, uint256 apTokenSupply) internal view {
        if (apTokenSupply > 0) {
            uint256 secondsElapsed = block.timestamp - farm.lastRewardTimestamp;
            uint256 joeReward = secondsElapsed * farm.joePerSec;
            farm.accJoePerShare = farm.accJoePerShare + (joeReward * ACC_TOKEN_PRECISION) / apTokenSupply;
        }

        farm.lastRewardTimestamp = block.timestamp;
    }

    /**
     * @dev Updates the farm's state if time passed since last update.
     * @dev Uses `_getNewFarmState` and commit the new farm state.
     * @param pid The index of the farm. See `_farmInfo`.
     */
    function _updateFarm(uint256 pid) internal returns (FarmInfo memory) {
        FarmInfo memory farm = _farmInfo[pid];

        if (farm.lastRewardTimestamp == 0) revert APTFarm__InvalidFarmIndex();

        if (block.timestamp > farm.lastRewardTimestamp) {
            uint256 apTokenSupply = apTokenBalances[farm.apToken];

            _refreshFarmState(farm, apTokenSupply);
            _farmInfo[pid] = farm;

            emit UpdateFarm(pid, farm.lastRewardTimestamp, apTokenSupply, farm.accJoePerShare);
        }

        return farm;
    }

    /**
     * @dev Harvests the pending JOE rewards for the given farm.
     * @param userAmount The amount of APT tokens staked by the user.
     * @param userRewardDebt The reward debt of the user.
     * @param pid The index of the farm. See `_farmInfo`.
     * @param farmAccJoePerShare The accumulated JOE per share of the farm.
     */
    function _harvest(
        uint256 userAmount,
        uint256 userRewardDebt,
        uint256 userUnpaidRewards,
        uint256 pid,
        uint256 farmAccJoePerShare
    ) internal returns (uint256) {
        uint256 pending = (userAmount * farmAccJoePerShare) / ACC_TOKEN_PRECISION - userRewardDebt + userUnpaidRewards;

        uint256 contractBalance = joe.balanceOf(address(this));
        if (contractBalance < pending) {
            userUnpaidRewards = pending - contractBalance;
            pending = contractBalance;
        } else {
            userUnpaidRewards = 0;
        }

        joe.safeTransfer(msg.sender, pending);

        emit Harvest(msg.sender, pid, pending, userUnpaidRewards);

        return userUnpaidRewards;
    }
}

