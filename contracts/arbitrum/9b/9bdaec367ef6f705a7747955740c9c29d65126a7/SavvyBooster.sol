// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "./Address.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./Ownable2StepUpgradeable.sol";
import "./EnumerableSet.sol";
import "./SafeERC20.sol";
import "./PausableUpgradeable.sol";

import "./ErrorMessages.sol";
import "./Mutex.sol";
import "./ISavvyBooster.sol";
import "./Checker.sol";
import "./Math.sol";
import "./Checker.sol";
import "./TokenUtils.sol";
import "./ErrorMessages.sol";

contract SavvyBooster is
    ISavvyBooster,
    Ownable2StepUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    Mutex
{
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @notice Scalar point to keep default fixed calculation.
    uint256 public constant FIXED_POINT_SCALAR = 1e18;

    /// @notice Array of pool info.
    PoolInfo[] private pools;

    /// @notice Info of user claims.
    mapping(address => UserInfo) private users;

    /// @notice User debt balances for each savvyPositionManager
    /// @dev userAddress => savvyPositionManager => userDebtBalances
    mapping(address => mapping(address => uint256)) private userDebtPerSavvy;

    /// @notice Total debt balances for each savvyPositionManager
    /// @dev savvyPositionManager => totalDebtBalances
    mapping(address => uint256) private totalDebtPerSavvy;

    /// @notice Handle of SavvyPositionManagers.
    EnumerableSet.AddressSet private savvyPositionManagers;

    /// @notice Reward Token.
    /// @dev Using protocol token ($SVY).
    IERC20 private svyToken;

    /// @notice ve Token.
    /// @dev Using vote eschrow token ($veSVY).
    IERC20 private veSvyToken;

    constructor() {
        _disableInitializers();
    }

    function initialize(
        IERC20 svyToken_,
        IERC20 veSvyToken_
    ) public initializer {
        Checker.checkArgument(
            Address.isContract(address(svyToken_)),
            "constructor: svyToken must be a valid contract"
        );
        Checker.checkArgument(
            Address.isContract(address(veSvyToken_)),
            "constructor: svyToken must be a valid contract"
        );

        svyToken = svyToken_;
        veSvyToken = veSvyToken_;
        __Ownable_init();
        __ReentrancyGuard_init_unchained();
        __Pausable_init_unchained();
    }

    modifier onlyVeSvyToken() {
        Checker.checkState(
            msg.sender == address(veSvyToken),
            "only veSvyToken can call this function"
        );
        _;
    }

    modifier onlySavvyPositionManager() {
        Checker.checkState(
            savvyPositionManagers.contains(msg.sender),
            "only savvyPositionManager can call this function"
        );
        _;
    }

    function getPools() external view returns (PoolInfo[] memory) {
        return pools;
    }

    function getUserInfo(address user) external view returns (UserInfo memory) {
        return users[user];
    }

    /// @inheritdoc ISavvyBooster
    function addSavvyPositionManagers(
        ISavvyPositionManager[] calldata _savvyPositionManagers
    ) external override onlyOwner {
        uint256 length = _savvyPositionManagers.length;
        Checker.checkArgument(length > 0, "empty SavvyPositionManager array");

        for (uint256 i = 0; i < length; i++) {
            address savvyPositionManager = address(_savvyPositionManagers[i]);
            Checker.checkArgument(
                !savvyPositionManagers.contains(savvyPositionManager),
                "same SavvyPositionManager already exist"
            );
            Checker.checkArgument(
                address(savvyPositionManager) != address(0),
                "zero SavvyPositionManager address"
            );
            Checker.checkArgument(
                Address.isContract(savvyPositionManager),
                "non-contract SavvyPositionManager address"
            );

            savvyPositionManagers.add(address(savvyPositionManager));
        }
    }

    /// @inheritdoc ISavvyBooster
    function addPool(
        uint256 amount_,
        uint256 duration_
    ) external override onlyOwner lock {
        Checker.checkArgument(amount_ > 0, "amount must be greater than zero");
        Checker.checkArgument(
            duration_ > 0,
            "duration must be greater than zero"
        );

        amount_ = TokenUtils.safeTransferFrom(
            address(svyToken),
            msg.sender,
            address(this),
            amount_
        );

        uint256 totalDebtBalance = 0;
        uint256 totalVeSvyBalance = 0;
        uint256 poolStart = block.timestamp;
        uint256 poolLength = pools.length;
        if (poolLength > 0) {
            PoolInfo memory lastPool = pools[poolLength - 1];
            poolStart = lastPool.startTime + lastPool.duration;
            totalDebtBalance = lastPool.totalDebtBalance;
            totalVeSvyBalance = lastPool.totalVeSvyBalance;
        }
        PoolInfo memory pool = PoolInfo({
            remainingEmissions: amount_,
            emissionRatio: amount_ / duration_,
            duration: duration_,
            startTime: poolStart,
            totalDebtBalance: totalDebtBalance,
            totalVeSvyBalance: totalVeSvyBalance
        });
        pools.push(pool);

        emit Deposit(amount_, poolLength);
    }

    /// @inheritdoc ISavvyBooster
    function removePool(uint256 period_) external override onlyOwner lock {
        uint256 currentTime = block.timestamp;
        uint256 currentPoolIndex = _getPoolIndex(currentTime);
        Checker.checkArgument(
            period_ > currentPoolIndex && period_ <= pools.length,
            "period must be for a queued future pool only"
        );

        PoolInfo memory poolToRemove = pools[period_ - 1];
        if (pools.length > 1) {
            for (uint256 i = period_ - 1; i < pools.length - 1; i++) {
                pools[i] = pools[i + 1];
                pools[i].startTime = pools[i].startTime - poolToRemove.duration;
            }
        }
        pools.pop();

        svyToken.safeTransfer(msg.sender, poolToRemove.remainingEmissions);

        emit Withdraw(poolToRemove.remainingEmissions);
    }

    /// @inheritdoc   ISavvyBooster
    function updatePendingRewardsWithVeSvy(
        address user_,
        uint256 userVeSvyBalance_,
        uint256 totalVeSvyBalance_
    ) external override nonReentrant whenNotPaused onlyVeSvyToken {
        uint256 currentTime = block.timestamp;
        uint256 currentPoolIndex = _getPoolIndex(currentTime);

        for (uint256 i = currentPoolIndex; i < pools.length; i++) {
            pools[i].totalVeSvyBalance = totalVeSvyBalance_;
        }

        uint256 pendingRewards = _getClaimableRewards(user_, currentTime);

        // Update UserInfo
        UserInfo storage user = users[user_];
        user.pendingRewards = pendingRewards;
        user.lastUpdateTime = currentTime;
        user.lastUpdatePool = currentPoolIndex;
        user.veSvyBalance = userVeSvyBalance_;
    }

    /// @inheritdoc	ISavvyBooster
    function updatePendingRewardsWithDebt(
        address user_,
        uint256 userDebtSavvy_,
        uint256 totalDebtSavvy_
    ) external override onlySavvyPositionManager nonReentrant whenNotPaused {
        address savvyPositionManager = msg.sender;
        uint256 currentTime = block.timestamp;
        uint256 currentPoolIndex = _getPoolIndex(currentTime);

        uint256 pendingRewards = _getClaimableRewards(user_, currentTime);
        uint256 userDebtBalance = _getUserDebt(
            user_,
            savvyPositionManager,
            userDebtSavvy_
        );
        userDebtPerSavvy[user_][savvyPositionManager] = userDebtSavvy_;
        _updateTotalDebt(
            savvyPositionManager,
            totalDebtSavvy_,
            currentPoolIndex
        );

        UserInfo storage user = users[user_];
        user.pendingRewards = pendingRewards;
        user.lastUpdateTime = currentTime;
        user.lastUpdatePool = currentPoolIndex;
        user.debtBalance = userDebtBalance;
    }

    /// @inheritdoc	ISavvyBooster
    function claimSvyRewards()
        external
        override
        nonReentrant
        whenNotPaused
        returns (uint256)
    {
        uint256 svyBalance = svyToken.balanceOf(address(this));
        Checker.checkState(svyBalance > 0, "no SVY emissions remaining");

        address account = msg.sender;
        uint256 currentTime = block.timestamp;
        uint256 currentPoolIndex = _getPoolIndex(currentTime);
        PoolInfo storage currentPool = pools[currentPoolIndex];
        Checker.checkState(
            currentPool.remainingEmissions <= svyBalance,
            "remaining emissions in the current pool cannot be more than SVY emissions in the contract"
        );

        uint256 claimableAmount = _getClaimableRewards(account, currentTime);
        Checker.checkState(claimableAmount > 0, "no claimable rewards");
        uint256 rewardAmount = Math.min(
            claimableAmount,
            currentPool.remainingEmissions
        );
        uint256 pendingRewards = claimableAmount - rewardAmount;

        currentPool.remainingEmissions -= rewardAmount;

        UserInfo storage user = users[account];
        user.pendingRewards = pendingRewards;
        user.lastUpdateTime = currentTime;
        user.lastUpdatePool = currentPoolIndex;

        svyToken.safeTransfer(account, rewardAmount);

        emit Claim(account, rewardAmount, pendingRewards);

        return rewardAmount;
    }

    /// @inheritdoc	ISavvyBooster
    function getClaimableRewards(
        address user_
    ) external view override returns (uint256) {
        uint256 currentTime = block.timestamp;
        return _getClaimableRewards(user_, currentTime);
    }

    /// @dev pause contract from accepting actions
    function pause() external onlyOwner whenNotPaused {
        _pause();
    }

    /// @dev cancel pause to accept actions
    function unpause() external onlyOwner whenPaused {
        _unpause();
    }

    /// @inheritdoc ISavvyBooster
    function withdraw() external onlyOwner whenPaused {
        uint256 amount = svyToken.balanceOf(address(this));
        if (amount > 0) {
            svyToken.safeTransfer(msg.sender, amount);
            emit Withdraw(amount);
        }
    }

    /// @inheritdoc ISavvyBooster
    function getSvyEarnRate(address user_) external view returns (uint256) {
        uint256 currentPoolIndex = _getPoolIndex(block.timestamp);
        uint256 collateralWeightRatio = _getCollateralWeightRatio(
            user_,
            currentPoolIndex
        );
        return _getSvyEarnRate(collateralWeightRatio, currentPoolIndex);
    }

    /// @notice Get claimable rewards
    /// @dev svyRewards = [svyEarnRate] x [elapsedTimeReward]
    /// @param user_ The address of a user
    /// @param currentTime_ The timestamp of current time
    /// @return claimableAmount claimable rewards
    function _getClaimableRewards(
        address user_,
        uint256 currentTime_
    ) internal view returns (uint256) {
        uint256 currentPoolIndex = _getPoolIndex(currentTime_);
        UserInfo memory user = users[user_];
        uint256 claimableAmount = users[user_].pendingRewards;
        for (uint256 i = user.lastUpdatePool; i <= currentPoolIndex; i++) {
            uint256 collateralWeightRatio = _getCollateralWeightRatio(user_, i);
            uint256 svyEarnRate = _getSvyEarnRate(collateralWeightRatio, i);
            uint256 elapsedTime = _getElaspedTime(
                user.lastUpdateTime,
                i,
                currentTime_
            );

            uint256 rewardAmount = svyEarnRate * elapsedTime;
            claimableAmount += rewardAmount;
        }

        return claimableAmount;
    }

    /// @notice Get the pool index based on the provided current time
    /// @dev The pool is determined by comparing the time value to the start time
    /// of each pool and the duration of the previous pool.
    /// @param timeValue_ The time value
    /// @return The pool index of the provided time value
    function _getPoolIndex(uint256 timeValue_) internal view returns (uint256) {
        uint256 poolLength = pools.length;
        Checker.checkState(poolLength > 0, "no pool");

        for (uint256 i = poolLength - 1; i >= 0; i--) {
            if (timeValue_ > pools[i].startTime) {
                return i;
            }
            require(i > 0, "time value is before first pool start time");
        }
        return 0;
    }

    /// @notice Get user collateral weight ratio.
    /// @dev collateralWeightRatio = userCollateralWeight / totalCollateralWeight.
    /// @param user_ The address of a user.
    /// @param poolIndex_ The pool index to get total collateral weight.
    /// @return Return user collateral weight.
    function _getCollateralWeightRatio(
        address user_,
        uint256 poolIndex_
    ) internal view returns (uint256) {
        uint256 userCollateralWeight = _getUserCollateralWeight(user_);
        uint256 totalCollateralWeight = _getTotalCollateralWeight(poolIndex_);
        return
            totalCollateralWeight == 0
                ? 0
                : userCollateralWeight / totalCollateralWeight;
    }

    /// @notice Get user collateral weight.
    /// @dev userCollateralWeight = sqrt([user’s total debt balance] x [user’s veSVY balance])
    /// @dev Cuz user info didn't update after last updates, it returns values calculate with last user value.
    /// @param user_ The address of a user.
    /// @return Return user collateral weight.
    function _getUserCollateralWeight(
        address user_
    ) internal view returns (uint256) {
        UserInfo memory user = users[user_];
        uint256 userDebtBalance = user.debtBalance;
        uint256 userVeSvyBalance = user.veSvyBalance;
        return _calculateBoost(userDebtBalance, userVeSvyBalance);
    }

    /// @notice Get total collateral weight.
    /// @dev totalCollateralWeight = sqrt([total debt balance] x [total veSVY balance])
    /// @param poolIndex_ The pool index to get total collateral weight.
    /// @return Return total collateral weight.
    function _getTotalCollateralWeight(
        uint256 poolIndex_
    ) internal view returns (uint256) {
        PoolInfo memory pool = pools[poolIndex_];
        uint256 totalDebtBalance = pool.totalDebtBalance;
        uint256 totalVeSvyBalance = pool.totalVeSvyBalance;
        return _calculateBoost(totalDebtBalance, totalVeSvyBalance);
    }

    /// @notice Calculate boost as square root of (debtBalance x veSvyBalance)
    /// @param debtBalance debt balance value
    /// @param veSvyBalance veSVY balance value
    /// @return Return calculated boost
    function _calculateBoost(
        uint256 debtBalance,
        uint256 veSvyBalance
    ) internal pure returns (uint256) {
        return Math.sqrt((debtBalance * veSvyBalance) / FIXED_POINT_SCALAR);
    }

    /// @notice Multiply collateralWeightRatio with pool's emission ratio to get svyEarnRate.
    /// @dev svyEarnRate = [collateralWeightRatio] x [svyEmissionsRatio]
    /// @param collateralWeightRatio_ .
    /// @param poolIndex_ The pool index to get svyEarnRate.
    /// @return Return svyEarnRate.
    function _getSvyEarnRate(
        uint256 collateralWeightRatio_,
        uint256 poolIndex_
    ) internal view returns (uint256) {
        uint256 emissionRatio = pools[poolIndex_].emissionRatio;
        return collateralWeightRatio_ * emissionRatio;
    }

    /// @notice Calculate new user debt balance.
    /// @param user_ The address of a user.
    /// @param savvyPositionManager_ The address of a savvyPositionManager for updating.
    /// @param userDebtSavvy_ User debt balance of a savvyPositionManager.
    /// @return userDebtBalance Updated user debt balance.
    function _getUserDebt(
        address user_,
        address savvyPositionManager_,
        uint256 userDebtSavvy_
    ) internal view returns (uint256) {
        uint256 lastDebtSavvy = userDebtPerSavvy[user_][savvyPositionManager_];
        uint256 lastUserDebt = users[user_].debtBalance;
        uint256 userDebtBalance = lastUserDebt - lastDebtSavvy + userDebtSavvy_;
        return userDebtBalance;
    }

    /// @notice Update total debt balance for Savvy protocol.
    /// @param savvyPositionManager_ The address of a savvyPositionManager for updating.
    /// @param totalDebtSavvy_ total debt balance of a savvyPositionManager.
    /// @param poolIndex_ The pool index of pool
    function _updateTotalDebt(
        address savvyPositionManager_,
        uint256 totalDebtSavvy_,
        uint256 poolIndex_
    ) internal {
        uint256 lastTotalDebtSavvy = totalDebtPerSavvy[savvyPositionManager_];
        uint256 lastTotalDebt = pools[poolIndex_].totalDebtBalance;
        uint256 totalDebtBalance = lastTotalDebt -
            lastTotalDebtSavvy +
            totalDebtSavvy_;
        for (uint256 i = poolIndex_; i < pools.length; i++) {
            pools[i].totalDebtBalance = totalDebtBalance;
        }
        totalDebtPerSavvy[savvyPositionManager_] = totalDebtSavvy_;
    }

    /// @notice Get elapsed time in a supplying pool.
    /// @param lastUpdateTime_ The last update time of a user.
    /// @param poolIndex_ The pool index of relevant pool.
    /// @param timeValue_ The time value.
    /// @return The timestamp of elapsed time.
    function _getElaspedTime(
        uint256 lastUpdateTime_,
        uint256 poolIndex_,
        uint256 timeValue_
    ) internal view returns (uint256) {
        uint256 startTime = Math.max(
            lastUpdateTime_,
            pools[poolIndex_].startTime
        );
        uint256 poolEndTime = pools[poolIndex_].startTime +
            pools[poolIndex_].duration;
        uint256 endTime = Math.min(timeValue_, poolEndTime);
        if (startTime >= endTime) {
            return 0;
        }
        return endTime - startTime;
    }

    uint256[100] private __gap;
}

