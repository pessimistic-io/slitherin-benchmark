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

/** @dev Provides scalable pools mapped by protocol reward category IDs.
 *       Categories are dynamic and may have weights adjusted as individual
 *       pools.
 *       Rewards are given in ERC20 (FOREX) and go into each category
 *       proportionally to their weights for the category users to claim.
 *       Pools may accept staking of a virtual number (no underlying asset),
 *       an ERC20 (not yet implemented) or an NFT (not yet implemented).
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
     * @dev Stakes into pool to start accruing rewards for pool.
     * @param account The account to stake with.
     * @param value The value to be staked.
     * @param poolId The pool ID to stake into.
     */
    function stake(
        address account,
        uint256 value,
        uint256 poolId
    ) external override returns (uint256 errorCode) {
        Pool storage pool = pools[poolId];
        // Check for staking permission.
        require(canStake(pool), "Unauthorized");
        // TODO: Add support for ERC20 & NFT LP tokens,
        require(pool.assetType == AssetType.None, "Not yet supported");
        // Try to claim before rewriting user deposit.
        claimForAccount(account);
        Deposit storage deposit = pool.deposits[account];
        // TODO: Correctly implement this for ERC20 & NFT LP tokens.
        updateDeposit(account, deposit.amount + value, poolId);
        emit Stake(account, poolId, value);
        return 0;
    }

    /**
     * @dev Returns the boosted stake value for an account and pool.
     * @param account The account to calculate the boosted value for.
     * @param value The provided stake value.
     * @param totalRealDeposits The liquidity to calculate the boosted value for.
     * @param boostWeight The account's boost wait for the calculation.
     */
    function getUserBoostedStake(
        address account,
        uint256 value,
        uint256 totalRealDeposits,
        uint256 boostWeight
    ) public view override returns (uint256) {
        // Return base value if the gFOREX data can't be fetched.
        if (address(governanceLock) == address(0) || value == 0) return value;
        uint256 totalSupply = governanceLock.totalSupply();
        // Prevent division by zero if total supply is zero.
        if (totalSupply == 0) return value;
        uint256 boost =
            (totalRealDeposits * boostWeight * 15) / (totalSupply * 10);
        uint256 total = value + boost;
        uint256 max = (value * 25) / 10;
        // Return the minimum between the boosted total and the value provided.
        return total > max ? max : total;
    }

    /**
     * @dev Unstakes from a pool to stop accruing rewards.
     * @param account The account to unstake with.
     * @param value The value to be unstaked.
     * @param poolId The poolId ID to unstake from.
     */
    function unstake(
        address account,
        uint256 value,
        uint256 poolId
    ) external override returns (uint256 errorCode) {
        Pool storage pool = pools[poolId];
        // Check for unstaking permission.
        require(canStake(pool), "Unauthorized");
        Deposit storage deposit = pool.deposits[account];
        // Return early if the account has nothing staked.
        if (deposit.amount == 0) return 1;
        // Try to claim before modifying deposit value due to unstaking.
        claimForAccount(account);
        // TODO: Add support for ERC20 & NFT LP tokens
        uint256 stakeAmount = deposit.amount;
        // Limit value instead of reverting.
        if (value > stakeAmount) value = stakeAmount;
        uint256 newAmount = stakeAmount - value;
        updateDeposit(account, newAmount, poolId);
        emit Unstake(account, poolId, value);
        return 0;
    }

    /**
     * @dev Updates a deposit amount and the S value.
     * @param account The account to update the deposit for.
     * @param amount The new deposit amount.
     * @param poolId The pool ID.
     */
    function updateDeposit(
        address account,
        uint256 amount,
        uint256 poolId
    ) private {
        Pool storage pool = pools[poolId];
        Deposit storage deposit = pool.deposits[account];
        // Current boosted deposit amount.
        uint256 currentDeposit =
            getUserBoostedStake(
                account,
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
            getUserBoostedStake(account, amount, pool.totalRealDeposits, newBoostWeight);
        pool.totalDeposits = currentDeposit > newDeposit // Unstaking.
            ? pool.totalDeposits - (currentDeposit - newDeposit) // Staking.
            : pool.totalDeposits + (newDeposit - currentDeposit);
        deposit.amount = amount;
    }

    /**
     * @dev Claims FOREX rewards for caller.
     */
    function claim() external override {
        claimForAccount(msg.sender);
    }

    /**
     * @dev Claims FOREX rewards for account.
     */
    function claimForAccount(address account) private {
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
            // Cache storage read values.
            uint256 depositS = deposit.S;
            uint256 poolS = pool.S;
            uint256 boostWeightBeforeClaim = deposit.boostWeight;
            // Refresh boost value & totalDeposits if needed, and update
            // deposit's S value.
            updateDeposit(account, deposit.amount, poolId);
            // Continue to next iteration if there is nothing to claim.
            if (depositS >= poolS) continue;
            uint256 boostedAmount =
                getUserBoostedStake(
                    account,
                    deposit.amount,
                    pool.totalRealDeposits,
                    boostWeightBeforeClaim
                );
            uint256 deltaS = poolS - depositS;
            uint256 amount = (boostedAmount * deltaS) / (1 ether);
            // Update event variables.
            amounts[i] = amount;
            totalAmount += amount;
        }
        // Return early if there is nothing to claim.
        if (totalAmount == 0) return;
        // Transfer total reward to user.
        forex.transfer(account, totalAmount);
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
        pool.weight = weight;
        pool.assetType = assetType;
        pool.assetAddress = assetAddress;
        addToEnabledPools(newPoolId);
        emit CreatePool(newPoolId, assetType, assetAddress, weight);
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
            pool.assetType = assetTypes[i];
            pool.assetAddress = assetAddresses[i];
            pool.weight = weights[i];
            poolIds[i] = i;
            setPoolAlias(aliases[i], i);
            emit CreatePool(i, assetTypes[i], assetAddresses[i], weights[i]);
        }
        enabledPools = poolIds;
        poolCount = count;
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
     *      To disable, a weight must be set to zero.
     *      Will emit events accordingly.
     * @param poolIds The array of pool IDs to configure.
     * @param weights The array of weights to configure.
     */
    function _setPools(uint256[] memory poolIds, uint256[] memory weights)
        private
    {
        uint256 enabledLength = poolIds.length;
        assert(enabledLength == weights.length);
        // Cache storage read.
        uint256 count = poolCount;
        // Set pool weights as required.
        for (uint256 i = 0; i < count; i++) {
            // Find whether this pool is to be disabled.
            bool foundInEnabled = false;
            uint256 foundEnabledIndex;
            for (uint256 j = 0; j < enabledLength; j++) {
                if (i != poolIds[j]) continue;
                foundInEnabled = true;
                foundEnabledIndex = j;
                break;
            }
            Pool storage pool = pools[poolIds[i]];
            // Disable pool if needed, otherwise override weight.
            pool.weight = !foundInEnabled ? 0 : weights[foundEnabledIndex];
        }
        enabledPools = poolIds;
        emit SetPoolWeights(poolIds, weights);
    }

    /**
     * @dev Checks whether account has the permission to stake or unstake.
     * @param pool The pool reference.
     */
    function canStake(Pool storage pool) private view returns (bool) {
        return ((pool.assetType != AssetType.None && pool.weight > 0) ||
            pool.stakerWhitelist[msg.sender]);
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
        (, uint256[] memory amounts, uint256[] memory deltaS) = getPoolsData();
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

    /**
     * @dev Sets or unsets a staking address as whitelisted from a pool.
     *      The whitelist is only used if the pool's asset type is None.
     */
    function setWhitelistedStaker(
        address staker,
        uint256 poolId,
        bool isWhitelisted
    ) external override onlyOperatorOrAdmin {
        pools[poolId].stakerWhitelist[staker] = isWhitelisted;
        emit WhitelistChanged(staker, poolId, isWhitelisted);
    }

    /** @dev Sets a pool hash alias. These are used to fetch similar pools
     *       of pools without relying on the ID directly, e.g. all minting
     *       rewards pool for the protocol fxTokens. The ID for those may be
     *       obtained by e.g. getPoolAlias(keccak256("minting" + tokenAddress))
     */
    function setPoolAlias(bytes32 hash, uint256 poolId)
        public
        override
        onlyOperatorOrAdmin
    {
        // The poolId gets added by 1 so that a value of zero can revert
        // to identify aliases that have not been set (see getPoolAlias).
        poolAliases[hash] = poolId + 1;
        emit PoolAliasChanged(poolId, hash);
    }

    /**
     * @dev Adds an item to the enabledPools array
     * @param poolId The poolId ID to push to the array.
     */
    function addToEnabledPools(uint256 poolId) private {
        uint256 count = enabledPools.length;
        for (uint256 i = 0; i < count; i++) {
            if (enabledPools[i] != poolId) continue;
            revert("Pushing duplicate pool ID");
        }
        enabledPools.push(poolId);
    }

    /**
     * @dev Calculates pool parameters for all enabled pools from the
     *      current block.
     */
    function getPoolsData()
        public
        view
        override
        returns (
            uint256[] memory poolRatios,
            uint256[] memory accruedAmounts,
            uint256[] memory deltaS
        )
    {
        uint256 enabledCount = enabledPools.length;
        poolRatios = new uint256[](enabledCount);
        accruedAmounts = new uint256[](enabledCount);
        deltaS = new uint256[](enabledCount);
        // Return early if there no pools enabled.
        if (enabledCount == 0) return (poolRatios, accruedAmounts, deltaS);
        // Return early after running once this block.
        if (block.timestamp == lastDistributionDate)
            return (poolRatios, accruedAmounts, deltaS);
        // Return early if rate is zero.
        if (forexDistributionRate == 0)
            return (poolRatios, accruedAmounts, deltaS);
        uint256 totalWeight = getTotalWeight();
        uint256 rate = forexDistributionRate;
        uint256 duration = block.timestamp - lastDistributionDate;
        uint256 amount = duration * rate;
        for (uint256 i = 0; i < enabledCount; i++) {
            Pool storage pool = pools[enabledPools[i]];
            if (pool.weight == 0) continue;
            poolRatios[i] = (pool.weight * (1 ether)) / totalWeight;
            if (pool.totalDeposits == 0) continue;
            accruedAmounts[i] = (amount * poolRatios[i]) / (1 ether);
            deltaS[i] = (accruedAmounts[i] * (1 ether)) / pool.totalDeposits;
        }
    }

    /**
     * @dev Returns a reward pool alias for the fxToken and pool category.
     * @param token The fxToken address to get the pool for.
     * @param category The reward category number.
     */
    function getFxTokenPoolAlias(address token, uint256 category)
        external
        view
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
        (, , uint256[] memory deltaS) = getPoolsData();
        uint256 count = enabledPools.length;
        for (uint256 i = 0; i < count; i++) {
            uint256 poolId = enabledPools[i];
            Pool storage pool = pools[poolId];
            Deposit storage deposit = pool.deposits[account];
            uint256 depositS = deposit.S;
            uint256 poolS = pool.S + deltaS[i];
            uint256 depositAmount = deposit.amount;
            depositAmount = getUserBoostedStake(
                account,
                depositAmount,
                pool.totalRealDeposits,
                deposit.boostWeight
            );
            if (depositAmount == 0 || depositS >= poolS) continue;
            uint256 deltaS = poolS - depositS;
            balance += (depositAmount * deltaS) / (1 ether);
        }
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
    function getTotalWeight() private view returns (uint256 totalWeight) {
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
            if (pool.totalDeposits == 0)
                continue;
            pool.totalRealDeposits = pool.totalDeposits;
        }
    }

    /** @dev Protected UUPS upgrade authorization function */
    function _authorizeUpgrade(address) internal override onlyAdmin {}
}

