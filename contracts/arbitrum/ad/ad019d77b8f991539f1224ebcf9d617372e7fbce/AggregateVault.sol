// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import { IGlpRebalanceRouter } from "./IGlpRebalanceRouter.sol";
import { INettedPositionTracker } from "./INettedPositionTracker.sol";
import { PositionManagerRouter, WhitelistedTokenRegistry } from "./PositionManagerRouter.sol";
import { ERC20 } from "./ERC20.sol";
import { SafeTransferLib } from "./SafeTransferLib.sol";
import { IRewardRouterV2 } from "./IRewardRouterV2.sol";
import { IAssetVault } from "./IAssetVault.sol";
import { IFeeEscrow } from "./IFeeEscrow.sol";
import { IVaultFeesAndHooks } from "./IVaultFeesAndHooks.sol";
import { AggregateVaultStorage } from "./AggregateVaultStorage.sol";
import { NettingMath } from "./NettingMath.sol";
import { Solarray } from "./Solarray.sol";
import { Auth, GlobalACL, KEEPER_ROLE, SWAP_KEEPER } from "./Auth.sol";
import {     UMAMI_TOTAL_VAULTS,     GMX_FEE_STAKED_GLP,     GMX_GLP_MANAGER,     GMX_GLP_REWARD_ROUTER,     GMX_FEE_STAKED_GLP,     GMX_GLP_CLAIM_REWARDS,     UNISWAP_SWAP_ROUTER } from "./constants.sol";
import { AssetVault } from "./AssetVault.sol";
import { GlpHandler } from "./GlpHandler.sol";
import { IPositionManager } from "./IPositionManager.sol";
import { Whitelist } from "./Whitelist.sol";
import { AggregateVaultHelper } from "./AggregateVaultHelper.sol";
import { Multicall } from "./Multicall.sol";
import { ISwapManager } from "./ISwapManager.sol";

enum Peripheral {
    FeeHookHelper,
    RebalanceRouter,
    NettedPositionTracker,
    GlpHandler,
    GlpYieldRewardRouter,
    Whitelist,
    AggregateVaultHelper,
    NettingMath,
    UniV3SwapManager
}

/// @title AggregateVault
/// @author Umami DAO
/// @notice Contains common logic for all asset vaults and core keeper interactions
contract AggregateVault is GlobalACL, PositionManagerRouter, AggregateVaultStorage, Multicall {
    using SafeTransferLib for ERC20;

    // EVENTS
    // ------------------------------------------------------------------------------------------

    event CollectVaultFees(
        uint256 totalVaultFee,
        uint256 performanceFeeInAsset,
        uint256 managementFeeInAsset,
        uint256 timelockYieldMintAmount,
        address _assetVault
    );
    event OpenRebalance(
        uint256 timestamp, uint256[5] nextVaultGlpAlloc, uint256[5] nextGlpComp, int256[5] adjustedPositions
    );
    event CloseRebalance(uint256 _timestamp);

    // CONSTANTS
    // ------------------------------------------------------------------------------------------

    ERC20 public constant fsGLP = ERC20(GMX_FEE_STAKED_GLP);

    constructor(
        Auth _auth,
        GlpHandler _glpHandler,
        uint256 _nettingPriceTolerance,
        uint256 _zeroSumPnlThreshold,
        WhitelistedTokenRegistry _registry
    ) GlobalACL(_auth) PositionManagerRouter(_registry) {
        AVStorage storage _storage = _getStorage();
        _storage.glpHandler = _glpHandler;
        _storage.glpRewardClaimAddr = GMX_GLP_CLAIM_REWARDS;
        _storage.shouldCheckNetting = true;
        _storage.nettedThreshold = 10;
        _storage.glpRebalanceTolerance = 500;
        _storage.nettingPriceTolerance = _nettingPriceTolerance;
        _storage.zeroSumPnlThreshold = _zeroSumPnlThreshold;
    }

    // DEPOSIT & WITHDRAW
    // ------------------------------------------------------------------------------------------

    /**
     * @notice Handles a deposit of a specified amount of an ERC20 asset into the AggregateVault from an account, with a deposit fee deducted.
     * @param asset The ERC20 token to be deposited.
     * @param _amount The amount of the asset to be deposited.
     * @param _account The address of the account from which the deposit will be made.
     * @return amountSansFee The deposited amount after deducting the deposit fee.
     */
    function handleDeposit(ERC20 asset, uint256 _amount, address _account) external onlyAssetVault returns (uint256) {
        require(_amount > 0, "AggregateVault: deposit amount must be greater than 0");
        require(_account != address(0), "AggregateVault: deposit account must be non-zero address");
        uint256 vaultId = getVaultIndex(address(asset));
        require(vaultId < 5, "AggregateVault: invalid vaultId");
        AssetVaultEntry storage vault = _getAssetVaultEntries()[vaultId];
        // collect fee
        uint256 amountSansFee = _amount - _collectDepositFee(vault, _amount);
        vault.epochDelta += int256(amountSansFee);
        return amountSansFee;
    }

    /**
     * @notice Handles a withdrawal of a specified amount of an ERC20 asset from the AggregateVault to an account, with a withdrawal fee deducted.
     * @param asset The ERC20 token to be withdrawn.
     * @param _amount The amount of the asset to be withdrawn.
     * @param _account The address of the account to which the withdrawal will be made.
     * @return amountSansFee The withdrawn amount after deducting the withdrawal fee.
     */
    function handleWithdraw(ERC20 asset, uint256 _amount, address _account) external onlyAssetVault returns (uint256) {
        require(_amount > 0, "AggregateVault: withdraw amount must be greater than 0");
        require(_account != address(0), "AggregateVault: withdraw account must be non-zero address");
        uint256 vaultId = getVaultIndex(address(asset));
        require(vaultId < 5, "AggregateVault: invalid vaultId");
        AssetVaultEntry storage vault = _getAssetVaultEntries()[vaultId];
        // send assets
        uint256 amountSansFee = _amount - _collectWithdrawalFee(vault, _amount);
        require(asset.balanceOf(address(this)) >= amountSansFee, "AggregateVault: buffer exhausted");
        _transferAsset(address(asset), _account, amountSansFee);
        vault.epochDelta -= int256(amountSansFee);
        return amountSansFee;
    }

    /**
     * @notice Allows a whitelisted user to deposit into the vault.
     * @param _asset The ERC20 token to be deposited.
     * @param _account The address of the user making the deposit.
     * @param _amount The amount of tokens to be deposited.
     * @param merkleProof The Merkle proof for whitelisting verification.
     */
    function whitelistedDeposit(ERC20 _asset, address _account, uint256 _amount, bytes32[] memory merkleProof)
        public
        onlyAssetVault
    {
        Whitelist whitelist = _getWhitelist();
        require(whitelist.isWhitelisted(address(_asset), _account, merkleProof), "AggregateVault: not whitelisted");
        if (whitelist.isWhitelistedPriority(address(_asset), _account)) {
            whitelist.whitelistDeposit(address(_asset), _account, _amount);
        } else {
            whitelist.whitelistDepositMerkle(address(_asset), _account, _amount, merkleProof);
        }
    }

    // REBALANCE
    // ------------------------------------------------------------------------------------------

    /**
     * @notice Opens the rebalance period and validates next rebalance state.
     * @param nextVaultGlpAlloc the next round GLP allocation in USD in 18 decimals.
     * @param nextGlpComp the next round GLP composition(proportion) in 18 decimals.
     * @param nextHedgeMatrix the next round external position notionals in USD in 18 decimals.
     * @param adjustedPositions aggregate external position notional per asset in USD in 18 decimals.
     */
    function openRebalancePeriod(
        uint256[5] memory nextVaultGlpAlloc,
        uint256[5] memory nextGlpComp,
        int256[5][5] memory nextHedgeMatrix,
        int256[5] memory adjustedPositions,
        int256[5][5] memory adjustedNettedHedgeMatrix,
        bytes memory _hook
    ) external onlyRole(KEEPER_ROLE) {
        // before rebalance hook
        _delegatecall(_getFeeHookHelper(), abi.encodeCall(IVaultFeesAndHooks.beforeOpenRebalancePeriod, _hook));
        VaultState storage vaultState = _getVaultState();
        require(!vaultState.rebalanceOpen, "AggregateVault: rebalance period already open");
        checkNettingConstraint(nextVaultGlpAlloc, nextGlpComp, nextHedgeMatrix, adjustedPositions);
        pauseDeposits();

        RebalanceState storage rebalanceState = _getRebalanceState();

        rebalanceState.glpAllocation = nextVaultGlpAlloc;
        rebalanceState.glpComposition = nextGlpComp;
        rebalanceState.externalPositions = nextHedgeMatrix;
        rebalanceState.aggregatePositions = adjustedPositions; // variable naming
        rebalanceState.epoch = vaultState.epoch;
        rebalanceState.adjustedExternalPositions = adjustedNettedHedgeMatrix;

        _setRebalancePPS(vaultState.rebalancePPS);
        vaultState.rebalanceOpen = true;

        emit OpenRebalance(block.timestamp, nextVaultGlpAlloc, nextGlpComp, adjustedPositions);
    }

    /**
     * @notice Closes a rebalance period and validates current state is valid.
     * @param _glpPrice glp price used to value vault glp. Should be the same as what was used in rebalance.
     */
    function closeRebalancePeriod(uint256 _glpPrice, bytes memory _hook) external onlyRole(KEEPER_ROLE) {
        VaultState storage vaultState = _getVaultState();
        require(vaultState.rebalanceOpen, "AggregateVault: no open rebalance period");

        uint256[5] memory dollarGlpBalance = _glpToDollarArray(_glpPrice);
        RebalanceState storage rebalanceState = _getRebalanceState();

        checkNettingConstraint(
            dollarGlpBalance,
            rebalanceState.glpComposition,
            rebalanceState.externalPositions,
            rebalanceState.aggregatePositions
        );

        _resetEpochDeltas();

        vaultState.rebalanceOpen = false;
        vaultState.glpAllocation = rebalanceState.glpAllocation;
        vaultState.aggregatePositions = rebalanceState.aggregatePositions;

        int256[5][5] memory exposureMatrix;
        int256[5][5] memory _nettedPositions;

        (_nettedPositions, exposureMatrix) = _getNettingMath().calculateNettedPositions(
            rebalanceState.adjustedExternalPositions, rebalanceState.glpComposition, rebalanceState.glpAllocation
        );

        _setNettedPositions(_nettedPositions);

        _setStateExternalPositions(rebalanceState);

        AssetVaultEntry[5] storage assetVaults = _getAssetVaultEntries();

        // collect fee at the end because it depends on tvl
        for (uint256 i = 0; i < 5; i++) {
            _collectVaultRebalanceFees(assetVaults[i]);
        }
        _setCheckpointTvls();

        unpauseDeposits();

        // note set last to not trigger internal pnl
        vaultState.epoch += 1;
        vaultState.lastRebalanceTime = block.timestamp;

        // after rebalance hook
        _delegatecall(_getFeeHookHelper(), abi.encodeCall(IVaultFeesAndHooks.afterCloseRebalancePeriod, _hook));
        emit CloseRebalance(block.timestamp);
    }

    /**
     * @notice Executes the vault cycle.
     * @dev assetPrices An array containing the prices of the 5 assets.
     * @dev glpPrice The price of GLP.
     */
    function cycle(uint256[5] memory, /*assetPrices*/ uint256 /*glpPrice*/ ) external onlyRole(KEEPER_ROLE) {
        (bytes memory ret) = _forwardToHelper(msg.data);
        _return(ret);
    }

    /**
     * @notice Executes a multicall in the context of the aggregate vault.
     * @param data the calls to be executed.
     * @return results the return values of each call.
     */
    function multicall(bytes[] calldata data)
        external
        payable
        onlyRole(KEEPER_ROLE)
        returns (bytes[] memory results, uint256[] memory gasEstimates)
    {
        (results, gasEstimates) = _multicall(data);
    }

    /**
     * @notice Checks if the netting constraint is satisfied for the given input values.
     * @dev Reverts if the netting constraint is not satisfied.
     * @param vaultGlpAlloc An array representing the allocation of GLP held by the vault.
     * @param glpComp An array representing the composition of the GLP token.
     * @param hedgeMatrix A 2D array representing the hedge matrix.
     * @param aggregatePositions An array representing the aggregate positions.
     */
    function checkNettingConstraint(
        uint256[5] memory vaultGlpAlloc,
        uint256[5] memory glpComp,
        int256[5][5] memory hedgeMatrix,
        int256[5] memory aggregatePositions
    ) public view {
        NettingMath.NettedState memory nettingState =
            NettingMath.NettedState({ glpHeld: vaultGlpAlloc, externalPositions: aggregatePositions });
        NettingMath.NettedParams memory nettingParams = NettingMath.NettedParams({
            vaultCumulativeGlpTvl: Solarray.arraySum(vaultGlpAlloc),
            glpComposition: glpComp,
            nettedThreshold: _getNettedThreshold()
        });
        if (_getStorage().shouldCheckNetting) {
            require(
                _getNettingMath().isNetted(nettingState, nettingParams, hedgeMatrix),
                "AggregateVault: netting constraint not satisfied"
            );
        }
    }

    // VIEWS
    // ------------------------------------------------------------------------------------------

    /**
     * @notice preview deposit fee
     * @param size The size of the deposit for which the fee is being calculated
     * @return totalDepositFee The calculated deposit fee
     */
    function previewDepositFee(uint256 size) public returns (uint256 totalDepositFee) {
        (bytes memory ret) = _forwardToFeeHookHelper(abi.encodeCall(IVaultFeesAndHooks.getDepositFee, (size)));
        (totalDepositFee) = abi.decode(ret, (uint256));
    }

    /**
     * @notice preview withdrawal fee
     * @param token The address of the token for which the withdrawal fee is being calculated
     * @param size The size of the withdrawal for which the fee is being calculated
     * @return totalWithdrawalFee The calculated withdrawal fee
     */
    function previewWithdrawalFee(address token, uint256 size) public returns (uint256 totalWithdrawalFee) {
        (bytes memory ret) = _forwardToFeeHookHelper(abi.encodeCall(IVaultFeesAndHooks.getWithdrawalFee, (token, size)));
        (totalWithdrawalFee) = abi.decode(ret, (uint256));
    }

    /**
     * @notice Get the index of the asset vault in the storage
     * @param _asset The address of the asset whose vault index is being queried
     * @return idx The index of the asset vault
     */
    function getVaultIndex(address _asset) public view returns (uint256 idx) {
        mapping(address => uint256) storage tokenToAssetVaultIndex = _getTokenToAssetVaultIndex();
        idx = tokenToAssetVaultIndex[_asset];
        // cannot check for it being 0 aka null value because there
        // is a vault at 0 index too
        AssetVaultEntry[5] storage assetVaults = _getAssetVaultEntries();
        require(assetVaults[idx].token == _asset, "AggregateVault: asset vault not found");
    }

    /**
     * @notice Gets the current asset vault price per share (PPS)
     * @param _assetVault The address of the asset vault whose PPS is being queried
     * @return _pps The current asset vault PPS
     */
    function getVaultPPS(address _assetVault) public returns (uint256 _pps) {
        (bytes memory ret) = _forwardToHelper(abi.encodeCall(this.getVaultPPS, (_assetVault)));
        (_pps) = abi.decode(ret, (uint256));
    }

    /**
     * @notice Gets the current asset vault total value locked (TVL)
     * @param _assetVault The address of the asset vault whose TVL is being queried
     * @return _tvl The current asset vault TVL
     */
    function getVaultTVL(address _assetVault) public returns (uint256 _tvl) {
        (bytes memory ret) = _forwardToHelper(abi.encodeCall(this.getVaultTVL, (_assetVault)));
        (_tvl) = abi.decode(ret, (uint256));
    }

    /**
     * @notice Preview the asset vault cap
     * @param _asset The address of the asset whose vault cap is being queried
     * @return The current asset vault cap
     */
    function previewVaultCap(address _asset) public view returns (uint256) {
        uint256 vidx = getVaultIndex(_asset);
        VaultState memory state = _getVaultState();
        return state.vaultCaps[vidx];
    }

    /**
     * @notice Check if the whitelist is enabled
     * @return - True if whitelist is enabled, false otherwise
     */
    function whitelistEnabled() public view returns (bool) {
        Whitelist whitelist = _getWhitelist();
        if (address(whitelist) != address(0)) return whitelist.whitelistEnabled();
        return false;
    }

    /**
     * @notice Check if rebalance period is open
     * @return - True if rebalnce period is open, false otherwise
     */
    function rebalanceOpen() public view returns (bool) {
        VaultState storage vaultState = _getVaultState();
        return vaultState.rebalanceOpen;
    }

    // CONFIG
    // ------------------------------------------------------------------------------------------

    /**
     * @notice Set the peripheral contract addresses
     * @param _peripheral The enum value of the peripheral type
     * @param _addr The address of the peripheral contract
     */
    function setPeripheral(Peripheral _peripheral, address _addr) external onlyConfigurator {
        AVStorage storage _storage = _getStorage();

        if (_peripheral == Peripheral.FeeHookHelper) {
            _storage.feeAndHookHelper = _addr;
        } else if (_peripheral == Peripheral.RebalanceRouter) {
            _storage.glpRebalanceRouter = IGlpRebalanceRouter(_addr);
        } else if (_peripheral == Peripheral.NettedPositionTracker) {
            _storage.nettedPositionTracker = INettedPositionTracker(_addr);
        } else if (_peripheral == Peripheral.GlpHandler) {
            _storage.glpHandler = GlpHandler(_addr);
        } else if (_peripheral == Peripheral.GlpYieldRewardRouter) {
            _storage.glpRewardClaimAddr = _addr;
        } else if (_peripheral == Peripheral.Whitelist) {
            _storage.whitelist = Whitelist(_addr);
        } else if (_peripheral == Peripheral.AggregateVaultHelper) {
            _storage.aggregateVaultHelper = _addr;
        } else if (_peripheral == Peripheral.NettingMath) {
            _storage.nettingMath = NettingMath(_addr);
        } else if (_peripheral == Peripheral.UniV3SwapManager) {
            _storage.uniV3SwapManager = ISwapManager(_addr);
        }
    }

    /**
     * @notice Add a new position manager to the list of position managers
     * @param _manager The address of the new position manager
     */
    function addPositionManager(IPositionManager _manager) external onlyConfigurator {
        IPositionManager[] storage positionManagers = _getPositionManagers();
        positionManagers.push(_manager);
    }

    /**
     * @notice Sets the vault fees
     * @param _performanceFee The performance fee value to set
     * @param _managementFee The management fee value to set
     * @param _withdrawalFee The withdrawal fee value to set
     * @param _depositFee The deposit fee value to set
     * @param _timelockBoostPercent The timelock boost percent value to set
     */
    function setVaultFees(
        uint256 _performanceFee,
        uint256 _managementFee,
        uint256 _withdrawalFee,
        uint256 _depositFee,
        uint256 _timelockBoostPercent
    ) external onlyConfigurator {
        _getStorage().vaultFees = VaultFees({
            performanceFee: _performanceFee,
            managementFee: _managementFee,
            withdrawalFee: _withdrawalFee,
            depositFee: _depositFee,
            timelockBoostAmount: _timelockBoostPercent
        });
    }

    /**
     * @notice Set fee watermarks for all asset vaults
     * @param _newWatermarks An array of new watermark values for each asset vault
     */
    function setFeeWatermarks(uint256[5] memory _newWatermarks) external onlyConfigurator {
        AssetVaultEntry[5] storage assetVaults = _getAssetVaultEntries();
        for (uint256 i = 0; i < 5; i++) {
            assetVaults[i].feeWatermarkPPS = _newWatermarks[i];
            assetVaults[i].feeWatermarkDate = block.timestamp;
        }
    }

    /**
     * @notice Update fee watermark for a specific asset vault
     * @param _vaultId The index of the asset vault to update
     * @param _feeWatermarkPPS The new fee watermark value
     */
    function updateFeeWatermarkVault(uint256 _vaultId, uint256 _feeWatermarkPPS) external onlyConfigurator {
        AssetVaultEntry[5] storage assetVaults = _getAssetVaultEntries();
        assetVaults[_vaultId].feeWatermarkDate = block.timestamp;
        assetVaults[_vaultId].feeWatermarkPPS = _feeWatermarkPPS;
    }

    /**
     * @notice Set the flag for checking netting constraints
     * @param _newVal The new boolean value for the flag
     */
    function setShouldCheckNetting(bool _newVal) external onlyConfigurator {
        AVStorage storage _storage = _getStorage();
        _storage.shouldCheckNetting = _newVal;
    }

    /**
     * @notice Set the netted threshold in bips for netting constraint
     * @param _newNettedThreshold The new netted threshold value
     */
    function setNettedThreshold(uint256 _newNettedThreshold) external onlyConfigurator {
        AVStorage storage _storage = _getStorage();
        _storage.nettedThreshold = _newNettedThreshold;
    }

    /**
     * @notice Set the zero sum threshold for netting position pnl
     * @param _zeroSumPnlThreshold The new zero sum pnl threshold value
     */
    function setZeroSumPnlThreshold(uint256 _zeroSumPnlThreshold) external onlyConfigurator {
        require(_zeroSumPnlThreshold > 0, "AggregateVault: _zeroSumPnlThreshold must be > 0");
        require(_zeroSumPnlThreshold < 1e18, "AggregateVault: _zeroSumPnlThreshold must be < 1e18");
        AVStorage storage _storage = _getStorage();
        _storage.zeroSumPnlThreshold = _zeroSumPnlThreshold;
    }

    /**
     * @notice Update asset vault receipt contracts
     * @param _assetVaults An array of new asset vault entries
     */
    function setAssetVaults(AssetVaultEntry[5] calldata _assetVaults) external onlyConfigurator {
        AssetVaultEntry[5] storage assetVaults = _getAssetVaultEntries();
        mapping(address => uint256) storage tokenToAssetVaultIndex = _getTokenToAssetVaultIndex();
        mapping(address => uint256) storage vaultToAssetVaultIndex = _getVaultToAssetVaultIndex();

        for (uint256 i = 0; i < _assetVaults.length; i++) {
            assetVaults[i] = _assetVaults[i];
            tokenToAssetVaultIndex[_assetVaults[i].token] = i;
            vaultToAssetVaultIndex[_assetVaults[i].vault] = i;
        }
    }

    /**
     * @notice Set vault caps for all asset vaults
     * @param _newCaps An array of new cap values for each asset vault
     */
    function setVaultCaps(uint256[5] memory _newCaps) external onlyConfigurator {
        VaultState storage state = _getVaultState();
        state.vaultCaps = _newCaps;
    }

    /**
     * @notice Set fee recipient and deposit fee escrow addresses
     * @param _recipient The address of the fee recipient
     * @param _depositFeeEscrow The address of the deposit fee escrow
     */
    function setFeeRecipient(address _recipient, address _depositFeeEscrow, address _withdrawalFeeEscrow)
        external
        onlyConfigurator
    {
        require(_recipient != address(0), "AggregateVault: !address(0)");
        require(_depositFeeEscrow != address(0), "AggregateVault: !address(0)");
        VaultState storage state = _getVaultState();
        state.feeRecipient = _recipient;
        state.depositFeeEscrow = _depositFeeEscrow;
        state.withdrawalFeeEscrow = _withdrawalFeeEscrow;
    }

    // INTERNAL
    // ------------------------------------------------------------------------------------------

    /**
     * @notice Collects vault rebalance fees, mints timelock shares and distributes them.
     */
    function _collectVaultRebalanceFees(AssetVaultEntry memory assetVault) internal {
        uint256 performanceFeeInAsset;
        uint256 managementFeeInAsset;
        uint256 timelockYieldMintAmount;
        uint256 totalVaultFee;
        VaultState storage vaultState = _getVaultState();
        (bytes memory ret) = _forwardToFeeHookHelper(
            abi.encodeCall(IVaultFeesAndHooks.getVaultRebalanceFees, (assetVault.token, vaultState.lastRebalanceTime))
        );
        (performanceFeeInAsset, managementFeeInAsset, timelockYieldMintAmount, totalVaultFee) =
            abi.decode(ret, (uint256, uint256, uint256, uint256));

        if (totalVaultFee > 0) {
            _transferAsset(assetVault.token, vaultState.feeRecipient, totalVaultFee);
        }
        if (timelockYieldMintAmount > 0 && assetVault.timelockYieldBoost != address(0)) {
            AssetVault(assetVault.vault).mintTimelockBoost(timelockYieldMintAmount, assetVault.timelockYieldBoost);
        }

        emit CollectVaultFees(
            totalVaultFee, performanceFeeInAsset, managementFeeInAsset, timelockYieldMintAmount, assetVault.vault
        );
    }

    /**
     * @notice Collects withdrawal fees and distributes them.
     */
    function _collectWithdrawalFee(AssetVaultEntry memory assetVault, uint256 size) internal returns (uint256) {
        uint256 totalWithdrawalFee;

        (bytes memory ret) =
            _forwardToFeeHookHelper(abi.encodeCall(IVaultFeesAndHooks.getWithdrawalFee, (assetVault.token, size)));
        (totalWithdrawalFee) = abi.decode(ret, (uint256));

        VaultState memory vaultState = _getVaultState();
        if (totalWithdrawalFee > 0) {
            _transferAsset(assetVault.token, vaultState.withdrawalFeeEscrow, totalWithdrawalFee);
        }
        return totalWithdrawalFee;
    }

    /**
     * @notice Collects deposit fees and distributes them.
     */
    function _collectDepositFee(AssetVaultEntry memory assetVault, uint256 size) internal returns (uint256) {
        uint256 totalDepositFee;

        (bytes memory ret) = _forwardToFeeHookHelper(abi.encodeCall(IVaultFeesAndHooks.getDepositFee, (size)));
        (totalDepositFee) = abi.decode(ret, (uint256));

        VaultState storage vaultState = _getVaultState();
        if (totalDepositFee > 0) {
            _transferAsset(assetVault.token, vaultState.depositFeeEscrow, totalDepositFee);
        }

        return totalDepositFee;
    }

    /**
     * @notice Resets the epoch deposit/withdraw delta for all asset vaults.
     */
    function _resetEpochDeltas() internal {
        AssetVaultEntry[5] storage assetVaults = _getAssetVaultEntries();
        for (uint256 i = 0; i < 5; i++) {
            assetVaults[i].epochDelta = int256(0);
        }
    }

    /**
     * @notice Sets the checkpoint TVL for all asset vaults.
     */
    function _setCheckpointTvls() internal {
        AssetVaultEntry[5] storage assetVaults = _getAssetVaultEntries();
        for (uint256 i = 0; i < 5; i++) {
            assetVaults[i].lastCheckpointTvl = getVaultTVL(assetVaults[i].vault);
        }
    }

    /**
     * @notice Sets the rebalance price per share for all asset vaults.
     */
    function _setRebalancePPS(uint256[5] storage rebalancePps) internal {
        AssetVaultEntry[5] storage assetVaults = _getAssetVaultEntries();
        for (uint256 i = 0; i < 5; i++) {
            rebalancePps[i] = getVaultPPS(assetVaults[i].vault);
        }
    }

    /**
     * @notice Converts GLP to a dollar array based on the current GLP price.
     */
    function _glpToDollarArray(uint256 _glpPrice) internal view returns (uint256[5] memory glpAsDollars) {
        uint256[5] memory _vaultGlpAttribution = _getVaultGlpAttribution();
        uint256 totalGlpAttribution = Solarray.arraySum(_vaultGlpAttribution);
        uint256 totalGlpBalance = fsGLP.balanceOf(address(this));
        for (uint256 i = 0; i < 5; i++) {
            uint256 glpBalance = totalGlpBalance * _vaultGlpAttribution[i] / totalGlpAttribution;
            glpAsDollars[i] = _glpPrice * glpBalance / 1e18;
        }
    }

    // UTILS
    // ------------------------------------------------------------------------------------------

    /**
     * @notice Pause deposits and withdrawals for the asset vaults
     */
    function pauseDeposits() public onlyRole(KEEPER_ROLE) {
        AssetVaultEntry[5] storage assetVaults = _getAssetVaultEntries();
        for (uint256 i = 0; i < assetVaults.length; i++) {
            IAssetVault(assetVaults[i].vault).pauseDepositWithdraw();
        }
    }

    /**
     * @notice Unpause deposits and withdrawals for the asset vaults
     */
    function unpauseDeposits() public onlyRole(KEEPER_ROLE) {
        AssetVaultEntry[5] storage assetVaults = _getAssetVaultEntries();
        for (uint256 i = 0; i < assetVaults.length; i++) {
            IAssetVault(assetVaults[i].vault).unpauseDepositWithdraw();
        }
    }

    /**
     * @notice Executes a delegate view to the specified target with the provided data and decodes the response as bytes.
     */
    function delegateview(address _target, bytes calldata _data) external returns (bool _success, bytes memory _ret) {
        (bool success, bytes memory ret) = address(this).call(abi.encodeCall(this.delegateviewRevert, (_target, _data)));
        require(!success, "AggregateVault: delegateViewRevert didn't revert");
        (_success, _ret) = abi.decode(ret, (bool, bytes));
    }

    /**
     * @notice Executes a delegate call to the specified target with the provided data and reverts on error.
     */
    function delegateviewRevert(address _target, bytes memory _data) external {
        (bool success, bytes memory ret) = _target.delegatecall(_data);
        bytes memory encoded = abi.encode(success, ret);
        /// @solidity memory-safe-assembly
        assembly {
            revert(add(encoded, 0x20), mload(encoded))
        }
    }

    /**
     * @notice Forwards a call to the helper contract with the provided calldata.
     */
    function _forwardToHelper(bytes memory _calldata) internal returns (bytes memory ret) {
        address aggregateVaultHelper = _getAggregateVaultHelper();
        ret = _delegatecall(aggregateVaultHelper, _calldata);
    }

    /**
     * @notice Forwards a call to the helper contract with the provided calldata.
     */
    function _forwardToFeeHookHelper(bytes memory _calldata) internal returns (bytes memory ret) {
        address feeHookHelper = _getFeeHookHelper();
        ret = _delegatecall(feeHookHelper, _calldata);
    }

    /**
     * @notice Returns the provided bytes data.
     */
    function _return(bytes memory _ret) internal pure {
        assembly {
            let length := mload(_ret)
            return(add(_ret, 0x20), length)
        }
    }

    /**
     * @notice Ensures the caller is the configurator.
     */
    function _onlyConfigurator() internal override onlyConfigurator { }

    /**
     * @notice Ensures the caller is permissioned to swap.
     */
    function _onlySwapIssuer() internal override onlyRole(SWAP_KEEPER) { }

    /**
     * @notice Validates the authorization for an execute call.
     */
    function _validateExecuteCallAuth() internal override onlyRole(KEEPER_ROLE) { }

    /**
     * @notice Helper function to make either an ETH transfer or ERC20 transfer
     * @param asset the asset to transfer
     * @param recipient is the receiving address
     * @param amount is the transfer amount
     */
    function _transferAsset(address asset, address recipient, uint256 amount) internal {
        ERC20(asset).safeTransfer(recipient, amount);
    }

    /**
     * @notice Ensures the caller is an asset vault.
     */
    modifier onlyAssetVault() {
        AssetVaultEntry[5] storage assetVaults = _getAssetVaultEntries();
        for (uint256 i = 0; i < UMAMI_TOTAL_VAULTS; ++i) {
            if (msg.sender == assetVaults[i].vault) {
                _;
                return;
            }
        }
        revert("AggregateVault: not asset vault");
    }
}

