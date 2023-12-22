// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;
pragma abicoder v2;

import "./Initializable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./UUPSUpgradeable.sol";
import "./SafeERC20.sol";
import "./IHandleComponent.sol";
import "./IHandle.sol";
import "./IRewardPool.sol";
import "./Roles.sol";
import "./GovernanceLock.sol";
import "./StakedErc20.sol";

/** @dev Provides scalable pools mapped by protocol reward category IDs.
 *       Categories are dynamic and may have weights adjusted as individual
 *       pools.
 *       Rewards are given in ERC20 (FOREX) and go into each category
 *       proportionally to their weights for the category users to claim.
 *       Alternatively, a specific pool may have FOREX deposited into it
 *       directly, "bypassing" the weights and automatic distribution.
 *       Pools may accept staking of:
 *         [1]: A virtual number (no underlying asset), which relies
 *              on a "staker whitelist". This is used for internal
 *              reward tracking and the stakers are other protocol
 *              contracts which stake for the users.
 *         [2]: An ERC20. Users stake an ERC20 and receive StakedErc20
 *              as a receipt/LP token representing their stake.
 *         [3]: An NFT. Not yet implemented.
 *       Pool weights may be adjusted by an external DAO voting contract
 *       that has the OPERATOR_ROLE role.
 */
contract RewardPool is
    IRewardPool,
    IHandleComponent,
    Initializable,
    UUPSUpgradeable,
    Roles,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;

    /** @dev The Handle contract interface */
    IHandle private handle;
    /** @dev The canonical FOREX token to be used for reward claiming.
     *       The contract assumes it always has sufficient balance to
     *       execute reward claims.
     */
    IERC20 public override forex;
    /** @dev Pool mapping from pool ID to Pool struct */
    mapping(uint256 => Pool) private pools;
    /** @dev Hash alias to pool pool ID */
    mapping(bytes32 => uint256) private poolAliases;
    /** @dev Array of enabled pools */
    uint256[] public enabledPools;
    /** @dev FOREX distribution rate per second */
    uint256 public forexDistributionRate;
    /** @dev Date at which the last distribution of FOREX happened */
    uint256 public lastDistributionDate;
    /** @dev Number of pools created */
    uint256 public poolCount;
    /** @dev The GovernanceLock contract */
    GovernanceLock governanceLock;

    /** @dev Proxy initialisation function */
    function initialize() public initializer {
        __UUPSUpgradeable_init();
        __AccessControl_init();
        __ReentrancyGuard_init();
        _setupRole(ADMIN_ROLE, msg.sender);
        _setRoleAdmin(OPERATOR_ROLE, ADMIN_ROLE);
        _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);
    }

    /**
     * @dev Setter for Handle contract reference
     * @param _handle The Handle contract address
     */
    function setHandleContract(address _handle) public override onlyAdmin {
        handle = IHandle(_handle);
        forex = IERC20(handle.forex());
    }

    /**
     * @dev Setter for the GovernanceLock contract reference
     * @param _governanceLock The GovernanceLock contract address
     */
    function setGovernanceLock(address _governanceLock) external onlyAdmin {
        governanceLock = GovernanceLock(_governanceLock);
    }

    /** @dev Getter for Handle contract address */
    function handleAddress() public view override returns (address) {
        return address(handle);
    }

    /**
     * @dev Stakes account into pool to start accruing rewards for pool.
     * @param account The account to stake with.
     * @param value The value to be staked.
     * @param poolId The pool ID to stake into.
     */
    function stake(
        address account,
        uint256 value,
        uint256 poolId
    ) external override nonReentrant returns (uint256 errorCode) {
        Pool storage pool = pools[poolId];
        // Check for staking permission.
        require(_canStake(account, pool), "RewardPool: unauthorised");
        require(
            pool.assetType == AssetType.None ||
                pool.assetType == AssetType.ERC20,
            "RewardPool: not yet supported"
        );
        // Try to claim before rewriting user deposit.
        _claimForAccount(account);
        // Load user deposit.
        Deposit storage deposit = pool.deposits[account];
        // Update user deposit.
        _updateDeposit(account, deposit.amount + value, poolId);
        // Mint any receipt tokens after staking as needed.
        _handleAssetsAfterStake(account, value, pool, deposit);
        emit Stake(account, poolId, value);
        return 0;
    }

    /**
     * @dev Returns the boosted stake value for an account and pool.
     * @param value The provided stake value.
     * @param totalRealDeposits The liquidity to calculate the boosted value for.
     * @param boostWeight The account's boost weight for the calculation.
     *        This is equal to the user's gFOREX balance.
     */
    function getUserBoostedStake(
        uint256 value,
        uint256 totalRealDeposits,
        uint256 boostWeight
    ) public view override returns (uint256) {
        // Return base value if the gFOREX data can't be fetched.
        if (address(governanceLock) == address(0) || value == 0) return value;
        uint256 totalSupply = governanceLock.totalSupply();
        // Prevent division by zero if total supply is zero.
        if (totalSupply == 0) return value;
        // The boost deposit amount is an amount of assets
        // deposited into this pool that the user will receive rewards for
        // even though they did not necessarily deposit these assets.
        // That is, if the user staked 100 WETH and their boost is 2.5x then
        // the boost deposit amount is 150 WETH (the user receives an extra reward
        // equivalent to if they had staked an extra 150 WETH).
        // In that example, the (boosted) user deposit is 100 + 150 WETH.
        // The boost deposit amount is calculated as 1.5x of the product of the
        // gFOREX market share of the user and the
        // total (unboosted) deposits in the reward pool.
        // So, as an example, if the user has 50% of all gFOREX supply,
        // the boost deposit amount will be 75% of the total deposits
        // of the reward pool.
        uint256 boostDepositAmount =
            (totalRealDeposits * boostWeight * 15) / (totalSupply * 10);
        // The boost value is added to the unboosted deposit.
        uint256 total = value + boostDepositAmount;
        // Limit the deposit boost to 2.5x.
        uint256 max = (value * 25) / 10;
        // Return the minimum between the boosted total and the value provided.
        return total > max ? max : total;
    }

    /**
     * @dev Unstakes account from a pool to stop accruing rewards.
     * @param account The account to unstake with.
     * @param value The value to be unstaked.
     * @param poolId The poolId ID to unstake from.
     */
    function unstake(
        address account,
        uint256 value,
        uint256 poolId
    ) external override nonReentrant returns (uint256 errorCode) {
        Pool storage pool = pools[poolId];
        // Check for unstaking permission.
        require(_canStake(account, pool), "RewardPool: unauthorised");
        Deposit storage deposit = pool.deposits[account];
        // Return early if the account has nothing staked.
        if (deposit.amount == 0) return 1;
        // Try to claim before modifying deposit value due to unstaking.
        _claimForAccount(account);
        uint256 stakeAmount = deposit.amount;
        // Limit value instead of reverting.
        if (value > stakeAmount) value = stakeAmount;
        uint256 newAmount = stakeAmount - value;
        _updateDeposit(account, newAmount, poolId);
        // Burn any receipt tokens after unstaking as needed,
        // and also return funds.
        _handleAssetsAfterUnstake(account, value, pool, deposit);
        emit Unstake(account, poolId, value);
        return 0;
    }

    /**
     * @dev Updates a deposit amount and the S value.
     * @param account The account to update the deposit for.
     * @param amount The new deposit amount.
     * @param poolId The pool ID.
     */
    function _updateDeposit(
        address account,
        uint256 amount,
        uint256 poolId
    ) private {
        Pool storage pool = pools[poolId];
        Deposit storage deposit = pool.deposits[account];
        // Current boosted deposit amount.
        uint256 currentDeposit =
            getUserBoostedStake(
                deposit.amount,
                pool.totalRealDeposits,
                deposit.boostWeight
            );
        // Update boostWeight with user's gFOREX balance if available.
        uint256 newBoostWeight =
            address(governanceLock) != address(0)
                ? governanceLock.balanceOf(account)
                : 0;
        deposit.boostWeight = newBoostWeight;
        // New boosted deposit amount, only used for the totalDeposits variable.
        if (amount == 0) {
            pool.totalDeposits = pool.totalDeposits - currentDeposit;
            pool.totalRealDeposits = pool.totalRealDeposits - deposit.amount;
            delete pool.deposits[account];
            return;
        }
        deposit.S = pool.S;
        pool.totalRealDeposits = deposit.amount > amount // Unstaking.
            ? pool.totalRealDeposits - (deposit.amount - amount) // Staking.
            : pool.totalRealDeposits + (amount - deposit.amount);
        uint256 newDeposit =
            getUserBoostedStake(amount, pool.totalRealDeposits, newBoostWeight);
        pool.totalDeposits = currentDeposit > newDeposit // Unstaking.
            ? pool.totalDeposits - (currentDeposit - newDeposit) // Staking.
            : pool.totalDeposits + (newDeposit - currentDeposit);
        deposit.amount = amount;
    }

    /**
     * @dev Recalculates and applies the current boost for an account.
     *      Ideally this would be execute for all account deposits
     *      at every block, but this is not feasible.
     *      This function allows external actors to make sure
     *      all boosts are fair and sufficiently up to date.
     * @param account The account to update the boost for.
     * @param poolIds An array of pool IDs to update the boost for.
     */
    function updateAccountBoost(address account, uint256[] memory poolIds)
        external
    {
        uint256 length = poolIds.length;
        for (uint256 i = 0; i < length; i++) {
            uint256 poolId = poolIds[i];
            Pool storage pool = pools[poolId];
            require(pool.totalDeposits > 0, "Pool not initialised");
            uint256 currentDepositAmount = pool.deposits[account].amount;
            require(currentDepositAmount > 0, "Account has not deposited");
            // Runs updateDeposit with the current deposit amount,
            // which triggers a recalculation of the boost value
            // using the current block timestamp.
            _updateDeposit(account, currentDepositAmount, poolId);
        }
    }

    /**
     * @dev Claims FOREX rewards for caller.
     */
    function claim() external override nonReentrant {
        _claimForAccount(msg.sender);
    }

    /**
     * @dev Claims FOREX rewards for account.
     */
    function _claimForAccount(address account) private {
        // Update distribution as required before claiming.
        distribute();
        assert(lastDistributionDate == block.timestamp);
        uint256 enabledCount = enabledPools.length;
        uint256[] memory amounts = new uint256[](enabledCount);
        uint256 totalAmount;
        for (uint256 i = 0; i < enabledCount; i++) {
            uint256 poolId = enabledPools[i];
            Pool storage pool = pools[poolId];
            Deposit storage deposit = pool.deposits[account];
            // Cache deposit S value before updating the deposit
            // with the current pool S value.
            // The difference between the pre-update S value
            // and the current pool S value is the delta S
            // used to calculate the claimable balance.
            uint256 depositS = deposit.S;
            // Cache pool S value.
            // This is up to date since this function calls distribute().
            uint256 poolS = pool.S;
            // Cache the gFOREX balance before claiming.
            uint256 boostWeightBeforeClaim = deposit.boostWeight;
            // Refresh boost value & totalDeposits if needed, and update
            // deposit's S value to the current pool's S value, which
            // resets the claimable balance to zero.
            _updateDeposit(account, deposit.amount, poolId);
            // Continue to next iteration if there is nothing to claim.
            if (depositS >= poolS) continue;
            uint256 boostedAmount =
                getUserBoostedStake(
                    deposit.amount,
                    pool.totalRealDeposits,
                    boostWeightBeforeClaim
                );
            // The difference of the current pool S
            // and the pre-update deposit S
            // is used to calculate the claimable amount for the user.
            uint256 deltaS = poolS - depositS;
            uint256 amount = (boostedAmount * deltaS) / (1 ether);
            // Update event variables.
            amounts[i] = amount;
            totalAmount += amount;
        }
        // Return early if there is nothing to claim.
        if (totalAmount == 0) return;
        // Transfer total reward to user.
        forex.safeTransfer(account, totalAmount);
        emit Claim(account, totalAmount, enabledPools, amounts);
    }

    /**
     * @dev Creates a new pool.
     * @param weight The pool weight.
     * @param assetType The asset type for the pool.
     * @param assetAddress The asset address for the pool, or zero if none.
     * @param poolIds The array of pools to keep enabled and configure.
     * @param weights The weight array relative to the pools array.
     */
    function createPool(
        uint256 weight,
        AssetType assetType,
        address assetAddress,
        uint256[] memory poolIds,
        uint256[] memory weights
    ) external override onlyOperatorOrAdmin {
        _setPools(poolIds, weights);
        // Create new pool.
        uint256 newPoolId = poolCount++;
        Pool storage pool = pools[newPoolId];
        _initialisePool(pool, assetType, assetAddress, weight, newPoolId);
        // Add to enabled pools only if the weight is not zero.
        if (weight > 0) _addToEnabledPools(newPoolId);
    }

    /**
     * @dev Allows for setting up multiple pools at once after deployment.
     * @param assetTypes The asset type array for each pool.
     * @param assetAddresses The asset addresses array for each pool.
     * @param weights The weight array relative to the pools array.
     * @param aliases The aliases for the pools.
     */
    function setupPools(
        AssetType[] memory assetTypes,
        address[] memory assetAddresses,
        uint256[] memory weights,
        bytes32[] memory aliases
    ) external override onlyOperatorOrAdmin {
        require(poolCount == 0, "Pools already initialised");
        uint256 count = assetTypes.length;
        assert(count == assetAddresses.length && count == weights.length);
        uint256[] memory poolIds = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            Pool storage pool = pools[i];
            poolIds[i] = i;
            _initialisePool(
                pool,
                assetTypes[i],
                assetAddresses[i],
                weights[i],
                i
            );
            setPoolAlias(aliases[i], i);
        }
        enabledPools = poolIds;
        poolCount = count;
    }

    function _initialisePool(
        Pool storage pool,
        AssetType assetType,
        address assetAddress,
        uint256 weight,
        uint256 poolId
    ) private {
        _validatePoolAssetTypeAndAddress(assetType, assetAddress);
        pool.assetType = assetType;
        pool.assetAddress = assetAddress;
        pool.weight = weight;
        if (assetAddress != address(0))
            _setWhitelistedStaker(assetAddress, poolId, true);
        emit CreatePool(poolId, assetType, assetAddress, weight);
    }

    /**
     * @dev Used to enable and disable pools.
     *      To disable, a weight must be set to zero.
     *      Will emit events accordingly.
     * @param poolIds] The array of poolIds] to configure.
     * @param weights The array of weights to configure.
     */
    function setPools(uint256[] memory poolIds, uint256[] memory weights)
        public
        override
        onlyOperatorOrAdmin
    {
        _setPools(poolIds, weights);
    }

    /**
     * @dev Used to enable and disable pools.
     *      All enabled pools must be within the poolIds and weights arrays,
     *      and they should have a weight greater than zero.
     *      Any pools not in poolIds will have their weights set to zero.
     *      Will emit events accordingly.
     * @param poolIds The array of pool IDs to configure.
     * @param weights The array of weights to configure.
     */
    function _setPools(uint256[] memory poolIds, uint256[] memory weights)
        private
    {
        uint256 argumentLength = poolIds.length;
        require(
            argumentLength == weights.length,
            "RewardPool: args length mismatch"
        );
        // Cache storage read.
        uint256 count = poolCount;
        // Set pool weights as required.
        for (uint256 i = 0; i < count; i++) {
            // Find whether this pool has been passed in the poolIds argument.
            bool inArgument = false;
            uint256 argumentIndex;
            for (uint256 j = 0; j < argumentLength; j++) {
                if (i != poolIds[j]) continue;
                inArgument = true;
                argumentIndex = j;
                break;
            }
            Pool storage pool = pools[i];
            if (!inArgument) {
                // If the pool was not passed in the argument,
                // set its weight to zero.
                pool.weight = 0;
                continue;
            }
            uint256 weight = weights[argumentIndex];
            require(weight > 0, "RewardPool: set zero-weight pool");
            // Set pool weight to the argument value.
            pool.weight = weight;
        }
        enabledPools = poolIds;
        emit SetPoolWeights(poolIds, weights);
    }

    /**
     * @dev Checks whether the sender has the permission to stake or unstake.
     * @param account The account to stake/unstake for.
     * @param pool The pool reference.
     */
    function _canStake(address account, Pool storage pool)
        private
        view
        returns (bool)
    {
        bool isErc20Pool = pool.assetType == AssetType.ERC20;
        bool isWhitelistedStaker = pool.stakerWhitelist[msg.sender];
        // Whether the sender can stake for the user.
        // They must either be whitelisted, or staking for themselves.
        bool isAuthorised = isWhitelistedStaker || msg.sender == account;
        // If staking in an ERC20 pool, users can stake for themselves.
        // Otherwise, the staker must be whitelisted.
        return isAuthorised && (isErc20Pool || isWhitelistedStaker);
    }

    /**
     * @dev Set the FOREX distribution rate per second.
     * @param rate The FOREX rate per second to distribute across pools.
     */
    function setForexDistributionRate(uint256 rate)
        external
        override
        onlyOperatorOrAdmin
    {
        // Return early if rates are the same.
        if (rate == forexDistributionRate) return;
        // Distribute outstanding FOREX before updating the rate.
        if (lastDistributionDate != block.timestamp) {
            distribute();
            assert(lastDistributionDate == block.timestamp);
        }
        forexDistributionRate = rate;
        emit SetForexDistributionRate(rate);
    }

    /**
     * @dev Distributes outstanding FOREX across pools.
     *      Updates the lastDistributionDate to the current block timestamp
     *      if successful.
     */
    function distribute() public override {
        // Return early after running once this block.
        if (block.timestamp == lastDistributionDate) return;
        (, uint256[] memory amounts, uint256[] memory deltaS, ) =
            getEnabledPoolsData();
        // Calculate seconds passed since last distribution.
        uint256 duration = block.timestamp - lastDistributionDate;
        // Update the last distribution date.
        lastDistributionDate = block.timestamp;
        // Return early if there are no amounts to distribute.
        if (amounts.length == 0) return;
        assert(amounts.length == deltaS.length);
        uint256 totalAmount = 0;
        // Cache storage read.
        uint256 count = enabledPools.length;
        for (uint256 i = 0; i < count; i++) {
            Pool storage pool = pools[enabledPools[i]];
            // Continue if there are no amounts or pool is disabled.
            if (amounts[i] == 0 || pool.weight == 0) continue;
            pool.S += deltaS[i];
            totalAmount += amounts[i];
        }
        emit ForexDistributed(
            duration,
            forexDistributionRate,
            totalAmount,
            enabledPools,
            amounts
        );
    }

    function distributeDirectlyForPool(uint256 poolId, uint256 amount)
        external
        override
        onlyOperatorOrAdmin
    {
        Pool storage pool = pools[poolId];
        require(pool.totalDeposits > 0, "RewardPool: pool is empty");
        // Add delta S value based on distribution amount.
        pool.S += (amount * (1 ether)) / pool.totalDeposits;
        emit ForexDistributedDirectly(poolId, amount);
    }

    /**
     * @dev Sets or unsets a staking address as whitelisted from a pool.
     *      The whitelist is only used if the pool's asset type is None.
     */
    function setWhitelistedStaker(
        address staker,
        uint256 poolId,
        bool isWhitelisted
    ) external override onlyOperatorOrAdmin {
        _setWhitelistedStaker(staker, poolId, isWhitelisted);
    }

    /**
     * @dev Sets or unsets a staking address as whitelisted from a pool.
     *      The whitelist is only used if the pool's asset type is None.
     */
    function _setWhitelistedStaker(
        address staker,
        uint256 poolId,
        bool isWhitelisted
    ) private {
        require(
            pools[poolId].stakerWhitelist[staker] != isWhitelisted,
            "RewardPool: already set"
        );
        pools[poolId].stakerWhitelist[staker] = isWhitelisted;
        emit WhitelistChanged(staker, poolId, isWhitelisted);
    }

    /** @dev Sets a pool hash alias. These are used to fetch similar pools
     *       of pools without relying on the ID directly, e.g. all minting
     *       rewards pool for the protocol fxTokens. The ID for those may be
     *       obtained by e.g. getPoolIdByAlias(keccak256("minting" + tokenAddress))
     */
    function setPoolAlias(bytes32 hash, uint256 poolId)
        public
        override
        onlyOperatorOrAdmin
    {
        // The poolId gets added by 1 so that a value of zero can revert
        // to identify aliases that have not been set (see getPoolIdByAlias).
        poolAliases[hash] = poolId + 1;
        emit PoolAliasChanged(poolId, hash);
    }

    /**
     * @dev Adds an item to the enabledPools array
     * @param poolId The poolId ID to push to the array.
     */
    function _addToEnabledPools(uint256 poolId) private {
        uint256 count = enabledPools.length;
        for (uint256 i = 0; i < count; i++) {
            if (enabledPools[i] != poolId) continue;
            revert("RewardPool: pushing duplicate pool ID");
        }
        enabledPools.push(poolId);
    }

    /**
     * @dev Calculates pool parameters for all enabled pools from the
     *      current block.
     *      Also returns an array of the enabled pool IDs.
     */
    function getEnabledPoolsData()
        public
        view
        override
        returns (
            uint256[] memory poolRatios,
            uint256[] memory accruedAmounts,
            uint256[] memory deltaS,
            uint256[] memory poolIds
        )
    {
        uint256 enabledCount = enabledPools.length;
        poolRatios = new uint256[](enabledCount);
        accruedAmounts = new uint256[](enabledCount);
        deltaS = new uint256[](enabledCount);
        poolIds = new uint256[](enabledCount);
        // Return early if there no pools enabled as all arrays are empty.
        if (enabledCount == 0)
            return (poolRatios, accruedAmounts, deltaS, poolIds);
        // Get total pools weight to calculate ratios.
        uint256 totalWeight = _getTotalWeight();
        // Initialise poolIds and ratios array.
        for (uint256 i = 0; i < enabledCount; i++) {
            // Set poolIds for this index.
            poolIds[i] = enabledPools[i];
            // Load pool from storage and set poolRatios for this index.
            Pool storage pool = pools[poolIds[i]];
            if (totalWeight == 0 || pool.weight == 0) continue;
            poolRatios[i] = (pool.weight * (1 ether)) / totalWeight;
        }
        // Check whether the function should return before the
        // reward accrual calculations.
        bool shouldReturnEarly =
            // Return early after running once this block, as
            // that means all the accrued and delta values are zero.
            block.timestamp == lastDistributionDate ||
                // Return early if rate is zero, for the same reason above.
                // Whenever the rate changes, a re-distribution occurs.
                // So if the rate is zero, the amount below would also be.
                forexDistributionRate == 0;
        if (shouldReturnEarly)
            return (poolRatios, accruedAmounts, deltaS, poolIds);
        uint256 rate = forexDistributionRate;
        uint256 duration = block.timestamp - lastDistributionDate;
        uint256 amount = duration * rate;
        for (uint256 i = 0; i < enabledCount; i++) {
            // Load pool from storage.
            Pool storage pool = pools[poolIds[i]];
            if (pool.weight == 0 || pool.totalDeposits == 0) continue;
            accruedAmounts[i] = (amount * poolRatios[i]) / (1 ether);
            deltaS[i] = (accruedAmounts[i] * (1 ether)) / pool.totalDeposits;
        }
    }

    /**
     * @dev Calculates delta S value for a single pool.
     */
    function _getPoolDeltaS(Pool storage pool) private view returns (uint256) {
        uint256 totalWeight = _getTotalWeight();
        uint256 totalDeposits = pool.totalDeposits;
        if (totalWeight == 0 || totalDeposits == 0) return 0;
        uint256 rate = forexDistributionRate;
        uint256 duration = block.timestamp - lastDistributionDate;
        // Amount accrued across all pools
        uint256 globalAmount = duration * rate;
        uint256 poolRatio = (pool.weight * (1 ether)) / totalWeight;
        uint256 poolAccruedAmount = (globalAmount * poolRatio) / (1 ether);
        return (poolAccruedAmount * (1 ether)) / totalDeposits;
    }

    /**
     * @dev Returns a reward pool alias for the fxToken and pool category.
     * @param token The fxToken address to get the pool for.
     * @param category The reward category number.
     */
    function getFxTokenPoolAlias(address token, uint256 category)
        external
        pure
        override
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(token, category));
    }

    /** @dev Returns a pool hash alias or reverts if not defined */
    function getPoolIdByAlias(bytes32 hash)
        public
        view
        override
        returns (bool found, uint256 poolId)
    {
        uint256 result = poolAliases[hash];
        if (result == 0) return (false, 0);
        return (true, result - 1);
    }

    /**
     * @dev Get pool data.
     * @param poolId The ID of the pool to view.
     */
    function getPool(uint256 poolId)
        external
        view
        override
        returns (
            uint256 weight,
            AssetType assetType,
            address assetAddress,
            uint256 totalDeposits,
            uint256 S,
            uint256 totalRealDeposits
        )
    {
        Pool storage pool = pools[poolId];
        return (
            pool.weight,
            pool.assetType,
            pool.assetAddress,
            pool.totalDeposits,
            pool.S,
            pool.totalRealDeposits
        );
    }

    /**
     * @dev Get deposit for address.
     * @param account The account to view.
     * @param poolId The ID of the pool to view.
     */
    function getDeposit(address account, uint256 poolId)
        external
        view
        override
        returns (Deposit memory)
    {
        return pools[poolId].deposits[account];
    }

    /**
     * @dev Returns the reward balance for an address.
     * @param account The address to fetch balance for.
     */
    function balanceOf(address account)
        public
        view
        override
        returns (uint256 balance)
    {
        (, , uint256[] memory deltaS, ) = getEnabledPoolsData();
        uint256 count = enabledPools.length;
        for (uint256 i = 0; i < count; i++) {
            uint256 poolId = enabledPools[i];
            Pool storage pool = pools[poolId];
            Deposit storage deposit = pool.deposits[account];
            uint256 poolS = pool.S + deltaS[i];
            balance += _calculateClaimBalance(
                poolS,
                pool.totalRealDeposits,
                deposit
            );
        }
    }

    /**
     * @dev Returns the reward balance for an address on a specific pool.
     * @param account The address to fetch balance for.
     * @param poolId The pool ID to fetch the balance for.
     */
    function poolBalanceOf(address account, uint256 poolId)
        external
        view
        override
        returns (uint256 balance)
    {
        Pool storage pool = pools[poolId];
        Deposit storage deposit = pool.deposits[account];
        // Get pool S including accrual not yet distributed.
        uint256 poolS = pool.S + _getPoolDeltaS(pool);
        return _calculateClaimBalance(poolS, pool.totalRealDeposits, deposit);
    }

    /**
     * @dev Returns the (boosted) reward balance on a specific pool.
     * @param poolS The pool S value to use for the calculation.
     * @param poolTotalRealDeposits The (non-boosted) pool deposits.
     * @param deposit The reference deposit struct for the account.
     */
    function _calculateClaimBalance(
        uint256 poolS,
        uint256 poolTotalRealDeposits,
        Deposit storage deposit
    ) private view returns (uint256) {
        uint256 depositS = deposit.S;
        // Get boosted deposit amount.
        uint256 depositAmount =
            getUserBoostedStake(
                deposit.amount,
                poolTotalRealDeposits,
                deposit.boostWeight
            );
        // Deposit S should never be greater than pool S,
        // but it could be equal.
        if (depositAmount == 0 || depositS >= poolS) return 0;
        uint256 deltaS = poolS - depositS;
        return (depositAmount * deltaS) / (1 ether);
    }

    /**
     * @dev View to return the length of the enabledPools array,
     *      because Solidity is a special snowflake.
     */
    function enabledPoolsLength() external view returns (uint256) {
        return enabledPools.length;
    }

    /**
     * @dev Returns the total weight for all enabled pools.
     */
    function _getTotalWeight() private view returns (uint256 totalWeight) {
        uint256 enabledCount = enabledPools.length;
        for (uint256 i = 0; i < enabledCount; i++) {
            totalWeight += pools[enabledPools[i]].weight;
        }
    }

    /**
     * @dev Sets totalRealDeposits to totalDeposits for all pools.
     *      Only works if totalRealDeposits is zero and totalDeposits is not.
     *      Should only be called before boosts are active due to the
     *      totalRealDeposits variable being added to the code as a fix.
     */
    function syncTotalRealDeposits() external onlyAdmin {
        uint256 count = poolCount;
        for (uint256 i = 0; i < count; i++) {
            Pool storage pool = pools[i];
            if (pool.totalDeposits == 0) continue;
            pool.totalRealDeposits = pool.totalDeposits;
        }
    }

    /**
     * @dev Behaviour to execute after user deposit is updated when
     *      staking into a pool.
     *      This triggers the collection of an ERC20 asset if the
     *      pool requires ERC20 staking, and mints receipt tokens.
     * @param account The address of the user staking.
     * @param amount The amount being staked.
     * @param pool The reward pool struct reference.
     * @param deposit The deposit struct reference for the user.
     */
    function _handleAssetsAfterStake(
        address account,
        uint256 amount,
        Pool storage pool,
        Deposit storage deposit
    ) private {
        if (pool.assetType != AssetType.ERC20) return;
        _depositErc20(amount, pool);
        _mintStakedErc20(account, amount, pool, deposit);
    }

    /**
     * @dev Behaviour to execute after user deposit is updated when
     *      unstaking from a pool.
     *      This triggers the return of an ERC20 asset if the
     *      pool requires ERC20 staking, and burns receipt tokens.
     * @param account The address of the user unstaking.
     * @param amount The amount being unstaked.
     * @param pool The reward pool struct reference.
     * @param deposit The deposit struct reference for the user.
     */
    function _handleAssetsAfterUnstake(
        address account,
        uint256 amount,
        Pool storage pool,
        Deposit storage deposit
    ) private {
        if (pool.assetType != AssetType.ERC20) return;
        _withdrawErc20(amount, pool);
        _burnStakedErc20(account, amount, pool, deposit);
    }

    /**
     * @dev Transfers in the deposit of ERC20 tokens from the sender.
     * @param amount The amount being staked.
     * @param pool The reward pool struct reference.
     */
    function _depositErc20(uint256 amount, Pool storage pool) private {
        assert(pool.assetAddress != address(0));
        StakedErc20 stakedErc20 = StakedErc20(pool.assetAddress);
        IERC20 depositToken = IERC20(stakedErc20.depositToken());
        depositToken.safeTransferFrom(msg.sender, address(this), amount);
    }

    /**
     * @dev Transfers out the deposit of ERC20 tokens to the sender.
     * @param amount The amount being unstaked.
     * @param pool The reward pool struct reference.
     */
    function _withdrawErc20(uint256 amount, Pool storage pool) private {
        assert(pool.assetAddress != address(0));
        StakedErc20 stakedErc20 = StakedErc20(pool.assetAddress);
        IERC20 depositToken = IERC20(stakedErc20.depositToken());
        depositToken.safeTransfer(msg.sender, amount);
    }

    /**
     * @dev Mints receipt ERC20 tokens to the user, ensuring their
     *      token balance is the same as their deposit amount.
     * @param account The address of the user staking.
     * @param amount The amount being staked.
     * @param pool The reward pool struct reference.
     * @param deposit The deposit struct reference for the user.
     */
    function _mintStakedErc20(
        address account,
        uint256 amount,
        Pool storage pool,
        Deposit storage deposit
    ) private {
        // The user's receipt token balance must be equal to
        // the user's deposit in the pool.
        StakedErc20 token = StakedErc20(pool.assetAddress);
        token.mint(account, amount);
        // This check is made in StakedErc20 prior to mint,
        // and also replicated here after mint.
        assert(deposit.amount == token.balanceOf(account));
    }

    /**
     * @dev Burns receipt ERC20 tokens to the user, ensuring their
     *      token balance is the same as their deposit amount.
     * @param account The address of the user unstaking.
     * @param amount The amount being unstaked.
     * @param pool The reward pool struct reference.
     * @param deposit The deposit struct reference for the user.
     */
    function _burnStakedErc20(
        address account,
        uint256 amount,
        Pool storage pool,
        Deposit storage deposit
    ) private {
        StakedErc20 token = StakedErc20(pool.assetAddress);
        token.burn(account, amount);
        // This check is made in StakedErc20 prior to burn,
        // and also replicated here after burn.
        assert(deposit.amount == token.balanceOf(account));
    }

    /**
     * @dev Validates that the asset type and address are correct.
     *      If the asset type is None, then the address must be zero.
     *      If it is not none, then the address must not be zero.
     * @param assetType The asset type.
     * @param assetAddress The asset address.
     */
    function _validatePoolAssetTypeAndAddress(
        AssetType assetType,
        address assetAddress
    ) private pure {
        // If the asset type is None, then the address must be zero.
        bool isValidNoAsset =
            (assetType == AssetType.None && assetAddress == address(0));
        // If the asset type is not None, then the address must not be zero.
        bool isValidAsset =
            (assetType != AssetType.None && assetAddress != address(0));
        require(
            isValidNoAsset || isValidAsset,
            "RewardPool: invalid type/address"
        );
    }

    /** @dev Protected UUPS upgrade authorization function */
    function _authorizeUpgrade(address) internal override onlyAdmin {}
}

