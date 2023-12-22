// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.17;

import "./SafeERC20.sol";
import "./IController.sol";
import "./ILiquidityPool.sol";
import "./LiquidityPoolVault.sol";
import "./Constants.sol";
import "./UnlimitedOwnable.sol";

/**
 * @notice User deposits into a lock pool
 * @custom:member poolShares Amount of lp shares deposited
 * @custom:member depositTime timestamp when the deposit happened
 */
struct UserPoolDeposit {
    uint256 poolShares;
    uint40 depositTime;
}

/**
 * @notice Aggregated Info about a users locked shares in a lock pool
 * @custom:member userPoolShares Amount of lp shares deposited
 * @custom:member unlockedPoolShares Amount of lp shares unlocked
 * @custom:member nextIndex The index of the next, not yet unlocked, UserPoolDeposit
 * @custom:member length The length of the UserPoolDeposit array
 * @custom:member deposits mapping of UserPoolDeposit; Each deposit is represented by one entry.
 */
struct UserPoolInfo {
    uint256 userPoolShares;
    uint256 unlockedPoolShares;
    uint128 nextIndex;
    uint128 length;
    mapping(uint256 => UserPoolDeposit) deposits;
}

/**
 * @notice Lock pool information
 * @custom:member lockTime Lock time of the deposit
 * @custom:member multiplier Multiplier of the deposit
 * @custom:member amount amount of collateral in this pool
 * @custom:member totalPoolShares amount of pool shares in this pool
 */
struct LockPoolInfo {
    uint40 lockTime;
    uint16 multiplier;
    uint256 amount;
    uint256 totalPoolShares;
}

/**
 * @title LiquidityPool
 * @notice LiquidityPool is a contract that allows users to deposit and withdraw liquidity.
 *
 * It follows most of the EIP4625 standard. Users deposit an asset and receive liquidity pool shares (LPS).
 * Users can withdraw their LPS at any time.
 * Users can also decide to lock their LPS for a period of time to receive a multiplier on their rewards.
 * The lock mechanism is realized by the pools in this contract.
 * Each pool defines a different lock period and multiplier.
 */
contract LiquidityPool is ILiquidityPool, UnlimitedOwnable, Initializable, LiquidityPoolVault {
    using SafeERC20 for IERC20Metadata;
    using Math for uint256;

    /* ========== CONSTANTS ========== */

    uint256 constant MAXIMUM_MULTIPLIER = 5 * FULL_PERCENT;

    uint256 constant MAXIMUM_LOCK_TIME = 365 days;

    /* ========== STATE VARIABLES ========== */

    /// @notice Controller contract.
    IController public immutable controller;

    /// @notice Time locked after the deposit.
    uint256 public defaultLockTime;

    /// @notice Relative fee to early withdraw non-locked shares.
    uint256 public earlyWithdrawalFee;

    /// @notice Time when the early withdrawal fee is applied shares.
    uint256 public earlyWithdrawalTime;

    /// @notice minimum amount of asset to stay in the pool.
    uint256 public minimumAmount;

    /// @notice Array of pools with different lock time and multipliers.
    LockPoolInfo[] public pools;

    /// @notice Last deposit time of a user.
    mapping(address => uint256) public lastDepositTime;

    /// @notice Mapping of UserPoolInfo for each user for each pool. userPoolInfo[poolId][user]
    mapping(uint256 => mapping(address => UserPoolInfo)) public userPoolInfo;

    // Storage gap
    uint256[50] ___gap;

    /* ========== CONSTRUCTOR ========== */

    /**
     * @notice Initialize the contract.
     * @param unlimitedOwner_ The address of the unlimited owner.
     * @param collateral_ The address of the collateral.
     * @param controller_ The address of the controller.
     */

    constructor(IUnlimitedOwner unlimitedOwner_, IERC20Metadata collateral_, IController controller_)
        LiquidityPoolVault(collateral_)
        UnlimitedOwnable(unlimitedOwner_)
    {
        controller = controller_;
    }

    /* ========== INITIALIZER ========== */

    /**
     * @notice Initialize the contract.
     * @param name_ The name of the pool's ERC20 liquidity token.
     * @param symbol_ The symbol of the pool's ERC20 liquidity token.
     * @param defaultLockTime_ The default lock time of the pool.
     * @param earlyWithdrawalFee_ The early withdrawal fee of the pool.
     * @param earlyWithdrawalTime_ The early withdrawal time of the pool.
     * @param minimumAmount_ The minimum amount of the pool (subtracted from available liquidity).
     */
    function initialize(
        string memory name_,
        string memory symbol_,
        uint256 defaultLockTime_,
        uint256 earlyWithdrawalFee_,
        uint256 earlyWithdrawalTime_,
        uint256 minimumAmount_
    ) public onlyOwner initializer {
        __ERC20_init(name_, symbol_);

        _updateDefaultLockTime(defaultLockTime_);
        _updateEarlyWithdrawalFee(earlyWithdrawalFee_);
        _updateEarlyWithdrawalTime(earlyWithdrawalTime_);
        _updateMinimumAmount(minimumAmount_);
    }

    /* ========== VIEW FUNCTIONS ========== */

    /**
     * @notice Returns the total available liquidity in the pool.
     * @return The total available liquidity in the pool.
     * @dev The available liquidity is reduced by the minimum amount to make sure no rounding errors occur when liquidity is
     * drained.
     */
    function availableLiquidity() public view returns (uint256) {
        uint256 _totalAssets = totalAssets();

        if (_totalAssets > minimumAmount) {
            _totalAssets -= minimumAmount;
        } else {
            _totalAssets = 0;
        }

        return _totalAssets;
    }

    /**
     * @notice Returns information about user's pool deposits. Including locked and unlocked pool shares, shares and assets.
     * @return userPools an array of UserPoolDetails. This informs about current user's locked and unlocked shares
     */
    function previewPoolsOf(address user_) external view returns (UserPoolDetails[] memory userPools) {
        userPools = new UserPoolDetails[](pools.length);

        for (uint256 i = 0; i < pools.length; ++i) {
            userPools[i] = previewPoolOf(user_, i);
        }
    }

    /**
     * @notice Returns information about user's pool deposits. Including locked and unlocked pool shares, shares and assets.
     * @param user_ the user to get the pool details for
     * @param poolId_ the id of the pool to preview
     * @return userPool the UserPoolDetails. This informs about current user's locked and unlocked shares
     */
    function previewPoolOf(address user_, uint256 poolId_) public view returns (UserPoolDetails memory userPool) {
        userPool.poolId = poolId_;
        userPool.totalPoolShares = userPoolInfo[poolId_][user_].userPoolShares;
        userPool.unlockedPoolShares = _totalUnlockedPoolShares(user_, poolId_);
        userPool.totalShares = _poolSharesToShares(userPool.totalPoolShares, poolId_);
        userPool.unlockedShares = _poolSharesToShares(userPool.unlockedPoolShares, poolId_);
        userPool.totalAssets = previewRedeem(userPool.totalShares);
        userPool.unlockedAssets = previewRedeem(userPool.unlockedShares);
    }

    /**
     * @notice Function to check if a user is able to transfer their shares to another address
     * @param user_ the address of the user
     * @return bool true if the user is able to transfer their shares
     */
    function canTransferLps(address user_) public view returns (bool) {
        uint256 transferLockTime = earlyWithdrawalTime > defaultLockTime ? earlyWithdrawalTime : defaultLockTime;
        return block.timestamp - lastDepositTime[user_] >= transferLockTime;
    }

    /**
     * @notice Function to check if a user is able to withdraw their shares, with a possible loss to earlyWithdrawalFee
     * @param user_ the address of the user
     * @return bool true if the user is able to withdraw their shares
     */
    function canWithdrawLps(address user_) public view returns (bool) {
        return block.timestamp - lastDepositTime[user_] >= defaultLockTime;
    }

    /**
     * @notice Returns a possible earlyWithdrawalFee for a user. Fee applies when the user withdraws after the earlyWithdrawalTime and before the defaultLockTime
     * @param user_ the address of the user
     * @return uint256 the earlyWithdrawalFee or 0
     */
    function userWithdrawalFee(address user_) public view returns (uint256) {
        return block.timestamp - lastDepositTime[user_] < earlyWithdrawalTime ? earlyWithdrawalFee : 0;
    }

    /**
     * @notice Preview function to convert locked pool shares to asset
     * @param poolShares_ the amount of pool shares to convert
     * @param poolId_ the id of the pool to convert
     * @return the amount of assets that would be received
     */
    function previewRedeemPoolShares(uint256 poolShares_, uint256 poolId_) external view returns (uint256) {
        return previewRedeem(_poolSharesToShares(poolShares_, poolId_));
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /**
     * @notice Deposits an amount of the collateral asset.
     * @param assets_ The amount of the collateral asset to deposit.
     * @param minShares_ The desired minimum amount to receive in exchange for the deposited collateral. Reverts otherwise.
     * @return The amount of shares received for the deposited collateral.
     */
    function deposit(uint256 assets_, uint256 minShares_) external updateUser(msg.sender) returns (uint256) {
        return _depositAsset(assets_, minShares_, msg.sender);
    }

    /**
     * @notice Deposits an amount of the collateral asset and locks it directly
     * @param assets_ The amount of the collateral asset to deposit.
     * @param minShares_ The desired minimum amount to receive in exchange for the deposited collateral. Reverts otherwise.
     * @param poolId_ Id of the pool to lock the deposit
     * @return The amount of shares received for the deposited collateral.
     */
    function depositAndLock(uint256 assets_, uint256 minShares_, uint256 poolId_)
        external
        verifyPoolId(poolId_)
        updateUser(msg.sender)
        returns (uint256)
    {
        // deposit assets and mint directly for this contract as we're locking the tokens right away
        uint256 shares = _depositAsset(assets_, minShares_, address(this));

        _lockShares(shares, poolId_, msg.sender);

        return shares;
    }

    /**
     * @notice Locks LPs for a user.
     * @param shares_ The amount of shares to lock.
     * @param poolId_ Id of the pool to lock the deposit
     */
    function lockShares(uint256 shares_, uint256 poolId_) external verifyPoolId(poolId_) {
        _transfer(msg.sender, address(this), shares_);
        _lockShares(shares_, poolId_, msg.sender);
    }

    /**
     * @dev deposits assets into the pool
     */
    function _depositAsset(uint256 assets_, uint256 minShares_, address receiver_) private returns (uint256) {
        uint256 shares = previewDeposit(assets_);

        require(shares >= minShares_, "LiquidityPool::_depositAsset: Bad slippage");

        _deposit(msg.sender, receiver_, assets_, shares);

        return shares;
    }

    /**
     * @dev Internal function to lock shares
     */
    function _lockShares(uint256 lpShares_, uint256 poolId_, address user_) private {
        LockPoolInfo storage poolInfo = pools[poolId_];

        uint256 newPoolShares =
            _convertToPoolShares(lpShares_, poolInfo.totalPoolShares, poolInfo.amount, Math.Rounding.Down);

        poolInfo.amount += lpShares_;
        poolInfo.totalPoolShares += newPoolShares;

        emit AddedToPool(poolId_, previewRedeem(lpShares_), lpShares_, newPoolShares);

        UserPoolInfo storage _userPoolInfo = userPoolInfo[poolId_][user_];
        _addUserPoolDeposit(_userPoolInfo, newPoolShares);
    }

    function _addUserPoolDeposit(UserPoolInfo storage _userPoolInfo, uint256 newPoolShares_) private {
        _userPoolInfo.userPoolShares += newPoolShares_;

        _userPoolInfo.deposits[_userPoolInfo.length] = UserPoolDeposit(newPoolShares_, uint40(block.timestamp));
        _userPoolInfo.length++;
    }

    /**
     * @notice Withdraws an amount of the collateral asset.
     * @param shares_ The amount of shares to withdraw.
     * @param minOut_ The desired minimum amount of collateral to receive in exchange for the withdrawn shares. Reverts otherwise.
     * @return The amount of collateral received for the withdrawn shares.
     */
    function withdraw(uint256 shares_, uint256 minOut_) external canWithdraw(msg.sender) returns (uint256) {
        return _withdrawShares(msg.sender, shares_, minOut_, msg.sender);
    }

    /**
     * @notice Unlocks and withdraws an amount of the collateral asset.
     * @param poolId_ the id of the pool to unlock the shares from
     * @param poolShares_ the amount of pool shares to unlock and withdraw
     * @param minOut_ the desired minimum amount of collateral to receive in exchange for the withdrawn shares. Reverts otherwise.
     * return the amount of collateral received for the withdrawn shares.
     */
    function withdrawFromPool(uint256 poolId_, uint256 poolShares_, uint256 minOut_)
        external
        canWithdraw(msg.sender)
        verifyPoolId(poolId_)
        updateUserPoolDeposits(msg.sender, poolId_)
        returns (uint256)
    {
        uint256 lpAmount = _unlockShares(msg.sender, poolId_, poolShares_);
        return _withdrawShares(address(this), lpAmount, minOut_, msg.sender);
    }

    /**
     * @notice Unlocks shares and returns them to the user.
     * @param poolId_ the id of the pool to unlock the shares from
     * @param poolShares_ the amount of pool shares to unlock
     * @return lpAmount the amount of shares unlocked
     */
    function unlockShares(uint256 poolId_, uint256 poolShares_)
        external
        verifyPoolId(poolId_)
        updateUserPoolDeposits(msg.sender, poolId_)
        returns (uint256 lpAmount)
    {
        lpAmount = _unlockShares(msg.sender, poolId_, poolShares_);
        _transfer(address(this), msg.sender, lpAmount);
    }

    /**
     * @dev Withdraws share frm the pool
     */
    function _withdrawShares(address user, uint256 shares, uint256 minOut, address receiver)
        private
        returns (uint256)
    {
        uint256 assets = previewRedeem(shares);

        require(assets >= minOut, "LiquidityPool::_withdrawShares: Bad slippage");

        // When user withdraws before earlyWithdrawalPeriod is over, they will be charged a fee
        uint256 feeAmount = userWithdrawalFee(receiver) * assets / FULL_PERCENT;
        if (feeAmount > 0) {
            assets -= feeAmount;
            emit CollectedEarlyWithdrawalFee(user, feeAmount);
        }

        _withdraw(user, receiver, user, assets, shares);

        return assets;
    }

    /**
     * @dev Internal function to unlock pool shares
     */
    function _unlockShares(address user_, uint256 poolId_, uint256 poolShares_) private returns (uint256 lpAmount) {
        require(poolShares_ > 0, "LiquidityPool::_unlockShares: Cannot withdraw zero shares");
        UserPoolInfo storage _userPoolInfo = userPoolInfo[poolId_][user_];

        if (poolShares_ == type(uint256).max) {
            poolShares_ = _userPoolInfo.unlockedPoolShares;
        } else {
            require(
                _userPoolInfo.unlockedPoolShares >= poolShares_,
                "LiquidityPool::_unlockShares: User does not have enough unlocked pool shares"
            );
        }

        // Decrease users unlocked pool shares
        unchecked {
            _userPoolInfo.unlockedPoolShares -= poolShares_;
            _userPoolInfo.userPoolShares -= poolShares_;
        }

        // transform
        LockPoolInfo storage poolInfo = pools[poolId_];
        lpAmount = _poolSharesToShares(poolShares_, poolId_);

        // Remove total pool shares
        poolInfo.totalPoolShares -= poolShares_;
        poolInfo.amount -= lpAmount;

        emit RemovedFromPool(user_, poolId_, poolShares_, lpAmount);
    }

    /**
     * @dev Converts Pool Shares to Shares
     */
    function _poolSharesToShares(uint256 poolShares_, uint256 poolId_) internal view returns (uint256) {
        if (pools[poolId_].totalPoolShares == 0) {
            return 0;
        } else {
            return pools[poolId_].amount * poolShares_ / pools[poolId_].totalPoolShares;
        }
    }

    /**
     * @dev Converts an amount of shares to the equivalent amount of pool shares
     */
    function _convertToPoolShares(
        uint256 newLps_,
        uint256 totalPoolShares_,
        uint256 lockedLps_,
        Math.Rounding rounding_
    ) private pure returns (uint256 newPoolShares) {
        return (newLps_ == 0 || totalPoolShares_ == 0)
            ? newLps_ * 1e12
            : newLps_.mulDiv(totalPoolShares_, lockedLps_, rounding_);
    }

    /**
     * @notice Previews the total amount of unlocked pool shares for a user
     * @param user_ the user to preview the unlocked pool shares for
     * @param poolId_ the id of the pool to preview
     * @return the total amount of unlocked pool shares
     */
    function _totalUnlockedPoolShares(address user_, uint256 poolId_) internal view returns (uint256) {
        (uint256 newUnlockedPoolShares,) = _previewPoolShareUnlock(user_, poolId_);
        return userPoolInfo[poolId_][user_].unlockedPoolShares + newUnlockedPoolShares;
    }

    /**
     * @dev Updates the user's pool deposit info. This function effectively unlockes the eligible pool shares.
     * It works by iterating over the user's deposits and unlocking the shares that have been locked for more than the
     * lock period.
     */
    function _updateUserPoolDeposits(address user_, uint256 poolId_) private {
        UserPoolInfo storage _userPoolInfo = userPoolInfo[poolId_][user_];

        (uint256 newUnlockedShares, uint256 nextIndex) = _previewPoolShareUnlock(user_, poolId_);

        if (newUnlockedShares > 0) {
            _userPoolInfo.nextIndex = uint128(nextIndex);
            _userPoolInfo.unlockedPoolShares += newUnlockedShares;
        }
    }

    /**
     * @notice Previews the amount of unlocked pool shares for a user, by iterating through the user's deposits.
     * @param user_ the user to preview the unlocked pool shares for
     * @param poolId_ the id of the pool to preview
     * @return newUnlockedPoolShares the total amount of new unlocked pool shares
     * @return newNextIndex the index of the next deposit to be unlocked
     */
    function _previewPoolShareUnlock(address user_, uint256 poolId_)
        private
        view
        returns (uint256 newUnlockedPoolShares, uint256 newNextIndex)
    {
        uint256 poolLockTime = pools[poolId_].lockTime;
        UserPoolInfo storage _userPoolInfo = userPoolInfo[poolId_][user_];

        uint256 depositsCount = _userPoolInfo.length;
        for (newNextIndex = _userPoolInfo.nextIndex; newNextIndex < depositsCount; newNextIndex++) {
            if (block.timestamp - _userPoolInfo.deposits[newNextIndex].depositTime >= poolLockTime) {
                // deposit can be unlocked
                newUnlockedPoolShares += _userPoolInfo.deposits[newNextIndex].poolShares;
            } else {
                break;
            }
        }
    }

    /* ========== PROFIT/LOSS FUNCTIONS ========== */

    /**
     * @notice deposits a protocol profit when a trader made a loss
     * @param profit_ the profit of the asset with respect to the asset multiplier
     * @dev the allowande of the sender needs to be sufficient
     */
    function depositProfit(uint256 profit_) external onlyValidLiquidityPoolAdapter {
        _asset.safeTransferFrom(msg.sender, address(this), profit_);

        emit DepositedProfit(msg.sender, profit_);
    }

    /**
     * @notice Deposits fees from the protocol into this liquidity pool. Distributes assets over the liquidity providers by increasing LP shares.
     * @param amount_ the amount of fees to deposit
     */
    function depositFees(uint256 amount_) external onlyValidLiquidityPoolAdapter {
        (uint256[] memory multipliedPoolValues, uint256 totalMultipliedValues) = _getPoolMultipliers();

        // multiply the supply by the full percent so we use the same multiplier as the locked pools
        uint256 lpSupplyMultiplied = totalSupply() * FULL_PERCENT;

        if (lpSupplyMultiplied > 0 && totalMultipliedValues > 0) {
            // calculate the asset amount_ with which to mint new lp tokens that will be distributed as a reward to the already locked lps
            uint256 assetsToMint = amount_ * totalMultipliedValues / (lpSupplyMultiplied + totalMultipliedValues);

            // transfer assets belonging to lps without the multiplier
            unchecked {
                _asset.safeTransferFrom(msg.sender, address(this), amount_ - assetsToMint);
            }

            uint256 newShares = previewDeposit(assetsToMint);

            // transfer assets belonging to lps with the multiplier
            _asset.safeTransferFrom(msg.sender, address(this), assetsToMint);
            // mint new shares to distribute to locked tps
            _mint(address(this), newShares);

            uint256 newPoolLpsLeft = newShares;
            for (uint256 i; i < multipliedPoolValues.length - 1; ++i) {
                uint256 newPoolLps = newShares * multipliedPoolValues[i] / totalMultipliedValues;
                newPoolLpsLeft -= newPoolLps;
                pools[i].amount += newPoolLps;
            }

            pools[multipliedPoolValues.length - 1].amount += newPoolLpsLeft;
        } else {
            _asset.safeTransferFrom(msg.sender, address(this), amount_);
        }

        emit DepositedFees(msg.sender, amount_);
    }

    /**
     * @notice requests payout of a protocol loss when a trader made a profit
     * @param loss_ the requested amount of the asset with respect to the asset multiplier
     * @dev pays out the loss when msg.sender is a registered liquidity pool adapter
     */
    function requestLossPayout(uint256 loss_) external onlyValidLiquidityPoolAdapter {
        require(loss_ <= availableLiquidity(), "LiquidityPool::requestLossPayout: Payout exceeds limit");
        _asset.safeTransfer(msg.sender, loss_);
        emit PayedOutLoss(msg.sender, loss_);
    }

    /**
     * @dev Returns all pool multipliers and the sum of all pool multipliers
     */
    function _getPoolMultipliers()
        private
        view
        returns (uint256[] memory multipliedPoolValues, uint256 totalMultipliedValues)
    {
        multipliedPoolValues = new uint256[](pools.length);

        for (uint256 i; i < multipliedPoolValues.length; ++i) {
            uint256 multiplier = pools[i].multiplier;
            if (multiplier > 0) {
                multipliedPoolValues[i] = pools[i].amount * multiplier;
                totalMultipliedValues += multipliedPoolValues[i];
            }
        }
    }

    /**
     * @dev Overwrite of the ERC20 function. Includes a check if the user is able to transfer their shares, which
     * depends on if the last deposit time longer ago than the defaultLockTime.
     */
    function _beforeTokenTransfer(address from, address to, uint256) internal view override {
        // We have to make sure that this is neither a mint or burn, nor a lock or unlock
        if (to != address(this) && from != address(this) && from != address(0) && to != address(0)) {
            _canTransfer(from);
        }
    }

    /* ========== ADMIN FUNCTIONS ========== */

    /**
     * @notice Add pool with a lock time and a multiplier
     * @param lockTime_ Deposit lock time in seconds
     * @param multiplier_ Multiplier that applies to the pool. 10_00 is multiplier of x1.1, 100_00 is x2.0.
     * @dev User receives the reward for the normal shares, and the reward for the locked shares additional to that.
     * This is why 10_00 will total to a x1.1 multiplier.
     */
    function addPool(uint40 lockTime_, uint16 multiplier_)
        external
        onlyOwner
        verifyPoolParameters(lockTime_, multiplier_)
        returns (uint256)
    {
        pools.push(LockPoolInfo(lockTime_, multiplier_, 0, 0));

        emit PoolAdded(pools.length - 1, lockTime_, multiplier_);

        return pools.length - 1;
    }

    /**
     * @notice Updates a lock pool
     * @param poolId_ Id of the pool to update
     * @param lockTime_ Deposit lock time in seconds
     * @param multiplier_ Multiplier that applies to the pool. 10_00 is multiplier of x1.1, 100_00 is x2.0.
     */
    function updatePool(uint256 poolId_, uint40 lockTime_, uint16 multiplier_)
        external
        onlyOwner
        verifyPoolId(poolId_)
        verifyPoolParameters(lockTime_, multiplier_)
    {
        if (lockTime_ > 0) {
            pools[poolId_].lockTime = lockTime_;
        }

        if (multiplier_ > 0) {
            pools[poolId_].multiplier = multiplier_;
        } else if (lockTime_ == 0) {
            // if both values are 0, unlock them and set multiplier to 0
            pools[poolId_].lockTime = 0;
            pools[poolId_].multiplier = 0;
        }

        emit PoolUpdated(poolId_, lockTime_, multiplier_);
    }

    /**
     * @notice Update default lock time
     * @param defaultLockTime_ default lock time
     */
    function updateDefaultLockTime(uint256 defaultLockTime_) external onlyOwner {
        _updateDefaultLockTime(defaultLockTime_);
    }

    /**
     * @notice Update default lock time
     * @param defaultLockTime_ default lock time
     */
    function _updateDefaultLockTime(uint256 defaultLockTime_) private {
        defaultLockTime = defaultLockTime_;

        emit UpdatedDefaultLockTime(defaultLockTime_);
    }

    /**
     * @notice Update early withdrawal fee
     * @param earlyWithdrawalFee_ early withdrawal fee
     */
    function updateEarlyWithdrawalFee(uint256 earlyWithdrawalFee_) external onlyOwner {
        _updateEarlyWithdrawalFee(earlyWithdrawalFee_);
    }

    /**
     * @notice Update early withdrawal fee
     * @param earlyWithdrawalFee_ early withdrawal fee
     */
    function _updateEarlyWithdrawalFee(uint256 earlyWithdrawalFee_) private {
        earlyWithdrawalFee = earlyWithdrawalFee_;

        emit UpdatedEarlyWithdrawalFee(earlyWithdrawalFee_);
    }

    /**
     * @notice Update early withdrawal time
     * @param earlyWithdrawalTime_ early withdrawal time
     */
    function updateEarlyWithdrawalTime(uint256 earlyWithdrawalTime_) external onlyOwner {
        _updateEarlyWithdrawalTime(earlyWithdrawalTime_);
    }

    /**
     * @notice Update early withdrawal time
     * @param earlyWithdrawalTime_ early withdrawal time
     */
    function _updateEarlyWithdrawalTime(uint256 earlyWithdrawalTime_) private {
        earlyWithdrawalTime = earlyWithdrawalTime_;

        emit UpdatedEarlyWithdrawalTime(earlyWithdrawalTime_);
    }

    /**
     * @notice Update minimum amount
     * @param minimumAmount_ minimum amount
     */
    function updateMinimumAmount(uint256 minimumAmount_) external onlyOwner {
        _updateMinimumAmount(minimumAmount_);
    }

    /**
     * @notice Update minimum amount
     * @param minimumAmount_ minimum amount
     */
    function _updateMinimumAmount(uint256 minimumAmount_) private {
        minimumAmount = minimumAmount_;

        emit UpdatedMinimumAmount(minimumAmount_);
    }

    function _updateUser(address user) private {
        lastDepositTime[user] = block.timestamp;
    }

    /* ========== RESTRICTION FUNCTIONS ========== */

    function _canTransfer(address user) private view {
        require(canTransferLps(user), "LiquidityPool::_canTransfer: User cannot transfer LP tokens");
    }

    function _canWithdrawLps(address user) private view {
        require(canWithdrawLps(user), "LiquidityPool::_canWithdrawLps: User cannot withdraw LP tokens");
    }

    function _onlyValidLiquidityPoolAdapter() private view {
        require(
            controller.isLiquidityPoolAdapter(msg.sender),
            "LiquidityPool::_onlyValidLiquidityPoolAdapter: Caller not a valid liquidity pool adapter"
        );
    }

    function _verifyPoolId(uint256 poolId) private view {
        require(pools.length > poolId, "LiquidityPool::_verifyPoolId: Invalid pool id");
    }

    function _verifyPoolParameters(uint256 lockTime, uint256 multiplier) private pure {
        require(lockTime <= MAXIMUM_LOCK_TIME, "LiquidityPool::_verifyPoolParameters: Invalid pool lockTime");
        require(multiplier <= MAXIMUM_MULTIPLIER, "LiquidityPool::_verifyPoolParameters: Invalid pool multiplier");
    }

    /* ========== MODIFIERS ========== */

    modifier updateUser(address user) {
        _updateUser(user);
        _;
    }

    modifier updateUserPoolDeposits(address user, uint256 poolId) {
        _updateUserPoolDeposits(user, poolId);
        _;
    }

    modifier canTransfer(address user) {
        _canTransfer(user);
        _;
    }

    modifier canWithdraw(address user) {
        _canWithdrawLps(user);
        _;
    }

    modifier verifyPoolId(uint256 poolId) {
        _verifyPoolId(poolId);
        _;
    }

    modifier verifyPoolParameters(uint256 lockTime, uint256 multiplier) {
        _verifyPoolParameters(lockTime, multiplier);
        _;
    }

    modifier onlyValidLiquidityPoolAdapter() {
        _onlyValidLiquidityPoolAdapter();
        _;
    }
}

