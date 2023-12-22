// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;
pragma abicoder v2;

import "./Initializable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./UUPSUpgradeable.sol";
import "./SafeMath.sol";
import "./SafeERC20.sol";
import "./ILiquidator.sol";
import "./IHandle.sol";
import "./ITreasury.sol";
import "./IValidator.sol";
import "./IfxKeeperPool.sol";
import "./IVaultLibrary.sol";
import "./IReferral.sol";
import "./IRewardPool.sol";
import "./HandlePausable.sol";

/**
 * @dev Implements a scalable pool for collectively funding liquidations.
 */
contract fxKeeperPool is
    IfxKeeperPool,
    IValidator,
    Initializable,
    UUPSUpgradeable,
    HandlePausable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeMath for uint256;
    using SafeMath for int256;
    using SafeERC20 for IERC20;

    uint256 public constant SCALE_FACTOR = 1e9;
    uint256 public constant DECIMAL_PRECISION = 1e9;

    /** @dev The Handle contract interface */
    IHandle private handle;
    /** @dev The Liquidator contract interface */
    ILiquidator private liquidator;
    /** @dev The Treasury contract interface */
    ITreasury private treasury;
    /** @dev The VaultLibrary contract interface */
    IVaultLibrary private vaultLibrary;

    /** @dev mapping(collateral => keeper pool data) */
    mapping(address => Pool) internal pools;

    /** @dev Ratio of liquidation fees sent to protocol, where 1 ETH = 100% */
    uint256 public override protocolFee;

    address private self;

    modifier validFxToken(address token) {
        require(handle.isFxTokenValid(token), "IF");
        _;
    }

    /** @dev Proxy initialisation function */
    function initialize() public initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        self = address(this);
    }

    /**
     * @dev Setter for Handle contract reference
     * @param _handle The Handle contract address
     */
    function setHandleContract(address _handle) public override onlyOwner {
        handle = IHandle(_handle);
        treasury = ITreasury(handle.treasury());
        liquidator = ILiquidator(handle.liquidator());
        vaultLibrary = IVaultLibrary(handle.vaultLibrary());
    }

    /** @dev Getter for Handle contract address */
    function handleAddress() public view override returns (address) {
        return address(handle);
    }

    /**
     * @dev Setter for protocolFee
     * @param ratio The protocol fee ratio
     */
    function setProtocolFee(uint256 ratio) external override onlyOwner {
        require(ratio <= 1 ether, "IA (0<=R<=1)");
        protocolFee = ratio;
    }

    /**
     * @dev Stakes fxToken into the keeper pool.
     * @param amount The amount to stake
     * @param fxToken The pool token address
     * @param referral The referral account
     */
    function stake(
        uint256 amount,
        address fxToken,
        address referral
    ) external override validFxToken(fxToken) notPaused nonReentrant {
        // Transfer token and add to total stake.
        require(
            IERC20(fxToken).allowance(msg.sender, self) >= amount,
            "fxKeeperPool: fxToken ERC20 allowance not met"
        );
        IReferral(handle.referral()).setReferral(msg.sender, referral);
        // Withdraw current rewards.
        Deposit storage deposit = pools[fxToken].deposits[msg.sender];
        if (deposit.snapshot.P > 0)
            _withdrawCollateralRewardFrom(msg.sender, fxToken);
        _checkInitialisePool(fxToken);
        // Transfer token and increase total deposits.
        IERC20(fxToken).safeTransferFrom(msg.sender, self, amount);
        pools[fxToken].totalDeposits = pools[fxToken].totalDeposits.add(amount);
        // Update deposit data.
        uint256 staked = balanceOfStake(msg.sender, fxToken);
        uint256 newDeposit = staked.add(amount);
        _updateDeposit(msg.sender, newDeposit, fxToken);
        // Withdraw existing collateral rewards.
        emit Stake(msg.sender, fxToken, amount);
    }

    /**
     * @dev Unstakes fxToken from the keeper pool.
     * @param amount The amount to unstake
     * @param fxToken The pool token address
     */
    function unstake(uint256 amount, address fxToken)
        external
        override
        validFxToken(fxToken)
        notPaused
        nonReentrant
    {
        // Get staked amount.
        uint256 stakedAmount = balanceOfStake(msg.sender, fxToken);
        // Limit requested unstake amount to maximum available.
        if (amount > stakedAmount) amount = stakedAmount;
        require(amount > 0, "IA");
        // Withdraw existing collateral rewards before proceeding.
        _withdrawCollateralRewardFrom(msg.sender, fxToken);
        // Subtract total staked amount for pool and send tokens to depositor.
        assert(pools[fxToken].totalDeposits >= amount);
        IERC20(fxToken).safeTransfer(msg.sender, amount);
        pools[fxToken].totalDeposits = pools[fxToken].totalDeposits.sub(amount);
        // Update deposit.
        uint256 newDeposit = stakedAmount.sub(amount);
        _updateDeposit(msg.sender, newDeposit, fxToken);
        emit Unstake(msg.sender, fxToken, amount);
    }

    /**
     * @dev Withdraws all collateral rewards from pool
     * @param fxToken The pool token address to withdraw rewards for
     */
    function withdrawCollateralReward(address fxToken)
        external
        override
        validFxToken(fxToken)
        notPaused
        nonReentrant
    {
        _withdrawCollateralRewardFrom(msg.sender, fxToken);
        // Update deposit.
        uint256 stake = balanceOfStake(msg.sender, fxToken);
        _updateDeposit(msg.sender, stake, fxToken);
    }

    /**
     * @dev Transfers collateral reward to staker.
            It is CRITICAL that after calling this function the _updateDeposit
            function is called so that the staker has its staking parameters
            reset to the current pool parameters to start accruing new rewards
           from this point forward.
     * @param account The staker address
     * @param fxToken The pool token address
     */
    function _withdrawCollateralRewardFrom(address account, address fxToken)
        private
    {
        if (pools[fxToken].snapshot.P == 0) return;
        // Withdraw all collateral rewards.
        (
            address[] memory collateralTokens,
            uint256[] memory collateralAmounts
        ) = balanceOfRewards(account, fxToken);
        assert(collateralTokens.length > 0);
        uint256 j = collateralTokens.length;
        for (uint256 i = 0; i < j; i++) {
            if (collateralAmounts[i] == 0) continue;
            uint256 collateralBalance =
                pools[fxToken].collateralBalances[collateralTokens[i]];
            // If the reward is greater than the pool amount, ignore loop iteration.
            if (collateralBalance < collateralAmounts[i]) continue;
            // Update total collateral balance.
            pools[fxToken].collateralBalances[
                collateralTokens[i]
            ] = collateralBalance.sub(collateralAmounts[i]);
            // Transfer the tokens.
            IERC20(collateralTokens[i]).safeTransfer(
                account,
                collateralAmounts[i]
            );
        }
        emit Withdraw(account, fxToken);
    }

    /**
     * @dev Retrieves account's current staked amount in pool
     * @param account The address to fetch balance from
     * @param fxToken The pool token address
     */
    function balanceOfStake(address account, address fxToken)
        public
        view
        override
        validFxToken(fxToken)
        returns (uint256 amount)
    {
        // Return zero if pool was not initialised.
        if (pools[fxToken].snapshot.P == 0) return 0;
        amount = pools[fxToken].deposits[account].amount;
        if (amount == 0) return 0;
        Snapshot storage dSnapshot = pools[fxToken].deposits[account].snapshot;
        Snapshot storage pSnapshot = pools[fxToken].snapshot;
        if (dSnapshot.epoch < pSnapshot.epoch) return 0;
        uint256 scaleDiff = pSnapshot.scale.sub(dSnapshot.scale);
        if (scaleDiff == 0) {
            amount = amount.mul(pSnapshot.P).div(dSnapshot.P);
        } else if (scaleDiff == 1) {
            amount = amount.mul(pSnapshot.P).div(dSnapshot.P).div(SCALE_FACTOR);
        } else {
            amount = 0;
        }
    }

    /**
     * @dev Retrieves account's current reward amount in pool
     * @param account The address to fetch rewards from
     * @param fxToken The pool token address
     */
    function balanceOfRewards(address account, address fxToken)
        public
        view
        override
        validFxToken(fxToken)
        returns (
            address[] memory collateralTypes,
            uint256[] memory collateralAmounts
        )
    {
        Pool storage pool = pools[fxToken];
        Deposit storage deposit = pool.deposits[account];
        // User never deposited if P is zero.
        if (deposit.snapshot.P == 0) {
            collateralTypes = new address[](0);
            collateralAmounts = new uint256[](0);
            return (collateralTypes, collateralAmounts);
        }
        collateralTypes = handle.getAllCollateralTypes();
        uint256 j = collateralTypes.length;
        collateralAmounts = new uint256[](j);
        uint256 stake = balanceOfStake(account, fxToken);
        uint256 portions;
        for (uint256 i = 0; i < j; i++) {
            {
                uint256 firstPortion =
                    pool.epochToScaleToCollateralToSum[deposit.snapshot.epoch][
                        deposit.snapshot.scale
                    ][collateralTypes[i]]
                        .sub(deposit.collateralToSum[collateralTypes[i]]);
                uint256 secondPortion =
                    pool.epochToScaleToCollateralToSum[deposit.snapshot.epoch][
                        deposit.snapshot.scale.add(1)
                    ][collateralTypes[i]]
                        .div(SCALE_FACTOR);
                portions = firstPortion.add(secondPortion);
            }
            collateralAmounts[i] = stake
                .mul(portions)
                .div(deposit.snapshot.P)
                .div(DECIMAL_PRECISION);
        }
    }

    /**
     * @dev Retrieves current stake share for account.
            18-digit ratio (1e18 = 100% of shares)
     * @param account The address to fetch the share from
     * @param fxToken The pool token address
     */
    function shareOf(address account, address fxToken)
        public
        view
        override
        validFxToken(fxToken)
        returns (uint256 share)
    {
        uint256 total = pools[fxToken].totalDeposits;
        if (total == 0) return 0;
        uint256 _stake = balanceOfStake(account, fxToken);
        share = _stake.mul(1 ether).div(total);
    }

    /**
     * @dev Attempt to liquidate vault.
     * @param account The address to perform liquidation on
     * @param fxToken The vault's fxToken address
     */
    function liquidate(address account, address fxToken)
        external
        override
        validFxToken(fxToken)
        notPaused
        nonReentrant
    {
        // Purchase collateral to restore vault's CR.
        (
            uint256 fxAmount,
            address[] memory collateralTypes,
            uint256[] memory collateralAmounts
        ) = executeLiquidation(account, fxToken);
        // Update pool state with new debt and collateral values.
        absorbDebt(fxAmount, collateralTypes, collateralAmounts, fxToken);
        emit Liquidate(account, fxToken, fxAmount);
    }

    /**
     * @dev Executes a liquidation using pool fxTokens.
             Reverts if pool does not have enough fxTokens to fund liquidation.
     * @param account The address to perform liquidation on
     * @param fxToken The vault's fxToken address
     */
    function executeLiquidation(address account, address fxToken)
        private
        returns (
            uint256 fxAmount,
            address[] memory collateralTypes,
            uint256[] memory collateralAmounts
        )
    {
        (fxAmount, collateralTypes, collateralAmounts) = liquidator.liquidate(
            account,
            fxToken
        );
        // Send protocol fees to fee recipient.
        uint256 j = collateralAmounts.length;
        address recipient = handle.FeeRecipient();
        for (uint256 i = 0; i < j; i++) {
            if (collateralAmounts[i] == 0) continue;
            uint256 fee = collateralAmounts[i].mul(protocolFee).div(1 ether);
            IERC20(collateralTypes[i]).safeTransfer(recipient, fee);
            collateralAmounts[i] = collateralAmounts[i].sub(fee);
        }
    }

    /**
     * @dev Updates pool parameters after performing a liquidation.
     * @param debt The debt absorbed during the liquidation.
     * @param collateralTypes The protocol array of collateral tokens.
     * @param collateralAmounts The array of collateral amounts purchased.
     * @param fxToken The fxToken address.
     */
    function absorbDebt(
        uint256 debt,
        address[] memory collateralTypes,
        uint256[] memory collateralAmounts,
        address fxToken
    ) private {
        Pool storage pool = pools[fxToken];
        if (pool.totalDeposits == 0 || debt == 0) return;
        assert(debt <= pool.totalDeposits);
        // Increase pool collateral balances.
        uint256 l = collateralTypes.length;
        for (uint256 i = 0; i < l; i++) {
            if (collateralAmounts[i] == 0) continue;
            pool.collateralBalances[collateralTypes[i]] = pools[fxToken]
                .collateralBalances[collateralTypes[i]]
                .add(collateralAmounts[i]);
        }
        _updateFxLossPerUnitStaked(
            debt,
            collateralTypes,
            collateralAmounts,
            pool
        );
        pool.totalDeposits = pool.totalDeposits.sub(debt);
        _updateCollateralGainSums(collateralTypes, collateralAmounts, pool);
        _updateSnapshotValues(debt, pool);
    }

    /**
     * @dev Updates the fxLossPerUnitStaked property in the pool struct
     * @param debtAbsorbed The debt absorbed by the pool
     * @param pool The pool reference
     */
    function _updateFxLossPerUnitStaked(
        uint256 debtAbsorbed,
        address[] memory collateralTypes,
        uint256[] memory collateralAmounts,
        Pool storage pool
    ) private {
        if (pool.totalDeposits == 0) {
            // Emptying pool.
            pool.fxLossPerUnitStaked = DECIMAL_PRECISION;
            pool.lastErrorFxLossPerUnitStaked = 0;
        } else {
            // Get numerator accounting for last error.
            uint256 lossNumerator =
                debtAbsorbed.mul(DECIMAL_PRECISION).sub(
                    pool.lastErrorFxLossPerUnitStaked
                );
            // Add one to have a larger fx loss ratio error to favour the pool.
            pool.fxLossPerUnitStaked = lossNumerator
                .div(pool.totalDeposits)
                .add(1);
            // Update error value.
            pool.lastErrorFxLossPerUnitStaked = pool
                .fxLossPerUnitStaked
                .mul(pool.totalDeposits)
                .sub(lossNumerator);
        }
    }

    /**
     * @dev Updates the collateral gain ratios and sums to be used for withdrawal
     * @param collateralTypes The collateral received type array
     * @param collateralAmounts The collateral received amount array
     * @param pool The Pool reference
     */
    function _updateCollateralGainSums(
        address[] memory collateralTypes,
        uint256[] memory collateralAmounts,
        Pool storage pool
    ) private {
        // Update collateral gain ratios.
        uint256 gainPerUnitStaked = 0;
        uint256 j = collateralTypes.length;
        for (uint256 i = 0; i < j; i++) {
            // Calculate gain numerator.
            uint256 gainNumerator =
                collateralAmounts[i].mul(DECIMAL_PRECISION).add(
                    pool.lastErrorCollateralGainRatio[collateralTypes[i]]
                );
            // Set gain per unit staked.
            gainPerUnitStaked = gainNumerator.div(pool.totalDeposits);
            // Update error for this collateral type.
            pool.lastErrorCollateralGainRatio[
                collateralTypes[i]
            ] = gainNumerator.sub(gainPerUnitStaked.mul(pool.totalDeposits));
            uint256 currentS =
                pool.epochToScaleToCollateralToSum[pool.snapshot.epoch][
                    pool.snapshot.scale
                ][collateralTypes[i]];
            uint256 marginalGain = gainPerUnitStaked.mul(pool.snapshot.P);
            // Update S.
            uint256 newS = currentS.add(marginalGain);
            pool.epochToScaleToCollateralToSum[pool.snapshot.epoch][
                pool.snapshot.scale
            ][collateralTypes[i]] = newS;
        }
    }

    /**
     * @notice Updates the fxLossPerUnitStaked property in the pool struct
     * @param fxLossPerUnitStaked The ratio of fx loss per unit staked
     * @param pool The pool reference
     */
    function _updateSnapshotValues(
        uint256 fxLossPerUnitStaked,
        Pool storage pool
    ) private {
        assert(pool.fxLossPerUnitStaked <= DECIMAL_PRECISION);
        uint256 currentP = pool.snapshot.P;
        uint256 newP;
        // Factor by which to change all deposits.
        uint256 newProductFactor =
            DECIMAL_PRECISION.sub(pool.fxLossPerUnitStaked);
        if (newProductFactor == 0) {
            // Emptied pool.
            pool.snapshot.epoch = pool.snapshot.epoch.add(1);
            pool.snapshot.scale = 0;
            newP = DECIMAL_PRECISION;
        } else if (
            currentP.mul(newProductFactor).div(DECIMAL_PRECISION) < SCALE_FACTOR
        ) {
            // Update scale due to P value.
            newP = currentP.mul(newProductFactor).mul(SCALE_FACTOR).div(
                DECIMAL_PRECISION
            );
            pool.snapshot.scale = pool.snapshot.scale.add(1);
        } else {
            newP = currentP.mul(newProductFactor).div(DECIMAL_PRECISION);
        }
        assert(newP > 0);
        pool.snapshot.P = newP;
    }

    /**
     * @dev Updates a staker's deposit parameters to the current pool parameters
            so that new rewards are accrued from this point forward.
     * @param account The vault account
     * @param amount The new deposit amount
     * @param fxToken The vault fxToken
     */
    function _updateDeposit(
        address account,
        uint256 amount,
        address fxToken
    ) private {
        Pool storage pool = pools[fxToken];
        pool.deposits[account].amount = amount;
        if (amount == 0) {
            delete pool.deposits[account];
            _setRewardStake(account, amount, fxToken);
            return;
        }
        // Update deposit snapshot.
        Snapshot storage poolSnapshot = pool.snapshot;
        Deposit storage deposit = pool.deposits[account];
        Snapshot storage depositSnapshot = deposit.snapshot;
        depositSnapshot.P = poolSnapshot.P;
        depositSnapshot.scale = poolSnapshot.scale;
        depositSnapshot.epoch = poolSnapshot.epoch;
        address[] memory collateralTypes = handle.getAllCollateralTypes();

        uint256 j = collateralTypes.length;
        for (uint256 i = 0; i < j; i++) {
            deposit.collateralToSum[collateralTypes[i]] = pool
                .epochToScaleToCollateralToSum[poolSnapshot.epoch][
                poolSnapshot.scale
            ][collateralTypes[i]];
        }
        _setRewardStake(account, amount, fxToken);
    }

    /**
     * @dev Sets the RewardPool stake amount
     * @param account The account to set the stake amount for
     * @param amount The new stake amount
     * @param fxToken The fxToken for the reward pool
     */
    function _setRewardStake(
        address account,
        uint256 amount,
        address fxToken
    ) private {
        // Update rewards stake.
        // Unstake from the reward pool.
        IRewardPool rewards = IRewardPool(handle.rewards());
        (bool found, uint256 rewardPoolId) =
            rewards.getPoolIdByAlias(
                rewards.getFxTokenPoolAlias(
                    fxToken,
                    uint256(RewardPoolCategory.Keeper)
                )
            );
        if (!found) return;
        // Re-stake new deposit amount.
        rewards.unstake(account, 2**256 - 1, rewardPoolId);
        if (amount > 0) rewards.stake(account, amount, rewardPoolId);
    }

    /**
     * @dev Initialises a pool, if necessary, by setting the P value to the
            decimal precision constant.
     * @param fxToken The pool token
     */
    function _checkInitialisePool(address fxToken) private {
        if (pools[fxToken].snapshot.P != 0) return;
        pools[fxToken].snapshot.P = DECIMAL_PRECISION;
    }

    /**
     * @dev Getter for the pool collateral balance.
     * @param fxToken The pool token
     * @param collateral The collateral token to get the balance for
     */
    function getPoolCollateralBalance(address fxToken, address collateral)
        external
        view
        override
        returns (uint256 amount)
    {
        return pools[fxToken].collateralBalances[collateral];
    }

    /**
     * @dev Getter for the pool deposit/stake amount.
     * @param fxToken The pool token
     */
    function getPoolTotalDeposit(address fxToken)
        external
        view
        override
        returns (uint256 amount)
    {
        return pools[fxToken].totalDeposits;
    }

    /** @dev Protected UUPS upgrade authorization function */
    function _authorizeUpgrade(address) internal override onlyOwner {}
}

