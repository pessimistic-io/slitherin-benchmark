// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import {AggregateVaultStorage} from "./AggregateVaultStorage.sol";
import {UMAMI_TOTAL_VAULTS, GMX_FEE_STAKED_GLP, GMX_GLP_REWARD_ROUTER, GMX_GLP_MANAGER, TOKEN_USDC, TOKEN_WETH, TOKEN_WBTC, TOKEN_LINK, TOKEN_UNI, UNISWAP_SWAP_ROUTER} from "./constants.sol";
import {ERC20} from "./ERC20.sol";
import {Solarray} from "./Solarray.sol";
import {AssetVault} from "./AssetVault.sol";
import {IPositionManager} from "./IPositionManager.sol";
import {GlpHandler} from "./GlpHandler.sol";
import {BaseHandler} from "./BaseHandler.sol";
import {INettedPositionTracker} from "./INettedPositionTracker.sol";
import {VaultMath} from "./VaultMath.sol";
import {IRewardRouterV2} from "./IRewardRouterV2.sol";
import {Multicall} from "./Multicall.sol";
import {SafeTransferLib} from "./SafeTransferLib.sol";
import {Solarray} from "./Solarray.sol";
import {PositionManagerRouter} from "./PositionManagerRouter.sol";
import {FeeEscrow} from "./FeeEscrow.sol";
import {LibRebalance} from "./LibRebalance.sol";
import {LibAggregateVaultUtils} from "./LibAggregateVaultUtils.sol";

ERC20 constant fsGLP = ERC20(GMX_FEE_STAKED_GLP);
uint constant BIPS = 10000;

/// @title AggregateVaultViews
/// @author Umami DAO
/// @notice A contract providing view functions for AggregateVaultStorage data.
contract AggregateVaultViews is AggregateVaultStorage {
    error RebalanceGlpAccountingError();

    /// @notice Returns the array of AssetVaultEntry structs.
    function getAssetVaultEntries()
        public
        view
        returns (AssetVaultEntry[5] memory _assetVaultEntry)
    {
        _assetVaultEntry = _getStorage().assetVaults;
    }

    /// @notice Returns the index of a token in the asset vault array.
    /// @param _token The address of the token.
    function tokenToAssetVaultIndex(
        address _token
    ) public view returns (uint _idx) {
        _idx = _getStorage().tokenToAssetVaultIndex[_token];
    }

    /// @notice Returns the index of a vault in the asset vault array.
    /// @param _vault The address of the vault.
    function vaultToAssetVaultIndex(
        address _vault
    ) public view returns (uint _idx) {
        _idx = _getStorage().vaultToAssetVaultIndex[_vault];
    }

    /// @notice Returns the current vault state.
    function getVaultState()
        public
        view
        returns (VaultState memory _vaultState)
    {
        _vaultState = _getStorage().vaultState;
    }

    /// @notice Returns the current rebalance state.
    function getRebalanceState()
        public
        view
        returns (RebalanceState memory _rebalanceState)
    {
        _rebalanceState = _getStorage().rebalanceState;
    }

    /// @notice Returns the current GLP attribution for each asset vault.
    function getVaultGlpAttribution()
        public
        view
        returns (uint[5] memory _glpAttribution)
    {
        _glpAttribution = _getStorage().vaultGlpAttribution;
    }

    /// @notice Returns the last netted price for a given epoch.
    /// @param _epoch The epoch for which to retrieve the netted price.
    function getLastNettedPrice(
        uint _epoch
    )
        public
        view
        returns (INettedPositionTracker.NettedPrices memory _nettedPrices)
    {
        _nettedPrices = _getStorage().lastNettedPrices[_epoch];
    }

    /// @notice Returns the array of position managers.
    function getPositionManagers()
        public
        view
        returns (IPositionManager[] memory _positionManagers)
    {
        _positionManagers = _getStorage().positionManagers;
    }

    /// @notice Returns the array of active aggregate positions.
    function getActiveAggregatePositions()
        public
        view
        returns (int[4] memory _activeAggregatePositions)
    {
        _activeAggregatePositions = _getStorage().activeAggregatePositions;
    }

    /// @notice Returns the array of netted positions.
    function getNettedPositions()
        public
        view
        returns (int[5][5] memory _nettedPositions)
    {
        _nettedPositions = _getStorage().nettedPositions;
    }

    /// @notice Returns the array of active external positions.
    function getActiveExternalPositions()
        public
        view
        returns (int[5][5] memory _activeExternalPositions)
    {
        _activeExternalPositions = _getStorage().activeExternalPositions;
    }

    /// @notice Returns the last GLP composition.
    function getLastGlpComposition()
        public
        view
        returns (uint[5] memory _glpComposition)
    {
        _glpComposition = _getStorage().lastGlpComposition;
    }
}

/// @title AggregateVaultHelper
/// @author Umami DAO
/// @notice Helper contract containting the vault operations and logic.
contract AggregateVaultHelper is AggregateVaultViews, BaseHandler, Multicall {
    using SafeTransferLib for ERC20;

    // EVENTS
    // ------------------------------------------------------------------------------------------

    event SettleNettedPositionPnl(uint256[5] previousGlpAmount, uint256[5] settledGlpAmount, int256[5] glpPnl, int256[5] dollarPnl, int256[5] percentPriceChange);
    event UpdateNettingCheckpointPrice(INettedPositionTracker.NettedPrices oldPrices, INettedPositionTracker.NettedPrices newPrices);
    event CompoundDistributeYield(uint256[5] glpYieldPerVault);
    event RebalanceGlpPosition(uint256[5] vaultGlpAttributionBefore, uint256[5] vaultGlpAttributionAfter, uint256[5] targetGlpAllocation, int256[5] totalVaultGlpDelta, int[5] feeAmounts);
    event GlpRewardClaimed(uint _amount);
    event Cycle(uint256 timestamp, uint256 round);

    // GETTERS
    // ------------------------------------------------------------------------------------------

    /**
    * @notice Gets the current asset vault price per share (PPS)
    * @param _assetVault The address of the asset vault
    * @return _pps The price per share of the asset vault
    */
    function getVaultPPS(
        address _assetVault
    ) public onlyDelegateCall returns (uint _pps) {
        VaultState memory vaultState = _getVaultState();
        if (vaultState.rebalanceOpen) {
            mapping(address => uint) storage vaultToAssetVaultIndex = _getVaultToAssetVaultIndex();
            return vaultState.rebalancePPS[vaultToAssetVaultIndex[_assetVault]];
        }

        uint idx = _getVaultToAssetVaultIndex()[_assetVault];
        AssetVaultEntry storage assetVault = _getAssetVaultEntry(idx);
        (uint tvl, , , ) = _getAssetVaultTvl(assetVault);
        uint oneShare = 10 ** ERC20(assetVault.vault).decimals();

        uint totalSupply = ERC20(assetVault.vault).totalSupply();
        if (totalSupply == 0) return oneShare;
        _pps = (tvl * oneShare) / totalSupply;
    }

    /**
    * @notice Gets the current Global Liquidity Position (GLP) for all vaults
    * @return _vaultsGlp An array containing the GLP for each vault
    */
    function getVaultsGlp() public view returns (uint[5] memory _vaultsGlp) {
        _vaultsGlp = LibAggregateVaultUtils.getVaultsGlp(_getStorage());
    }

    /**
    * @notice Gets the GLP for all vaults with no Profit and Loss (PNL) adjustments
    * @return _vaultsGlpNoPnl An array containing the GLP with no PNL for each vault
    */
    function getVaultsGlpNoPnl() public view returns (uint[5] memory _vaultsGlpNoPnl) {
        _vaultsGlpNoPnl = LibAggregateVaultUtils.getVaultsGlpNoPnl(_getStorage());
    }
    /**
    * @notice Gets the current asset vault Total Value Locked (TVL)
    * @param _assetVault The address of the asset vault
    * @return _tvl The total value locked in the asset vault
    */
    function getVaultTVL(
        address _assetVault
    ) public onlyDelegateCall returns (uint _tvl) {
        uint idx = _getVaultToAssetVaultIndex()[_assetVault];
        AssetVaultEntry storage assetVault = _getAssetVaultEntry(idx);
        (_tvl, , , ) = _getAssetVaultTvl(assetVault);
    }

    /**
    * @notice Gets the breakdown of the asset vault TVL
    * @param _assetVault The address of the asset vault
    * @return _total The total TVL in the asset vault
    * @return _buffer The buffer portion of the TVL
    * @return _glp The GLP portion of the TVL
    * @return _hedges The hedge portion of the TVL
    */
    function getVaultTVLBreakdown(
        address _assetVault
    )
        public
        onlyDelegateCall
        returns (uint _total, uint _buffer, uint _glp, uint _hedges)
    {
        (_total, _buffer, _glp, _hedges) = _getAssetVaultTvl(
            _getAssetVaultEntry(_getVaultToAssetVaultIndex()[_assetVault])
        );
    }

    // CONFIG
    // ------------------------------------------------------------------------------------------

    /**
    * @notice Sets the timelock yield boost for the specified vault
    * @param newTimelockYieldBoost The address of the new timelock yield boost
    * @param vaultIdx The index of the vault in the asset vaults array
    */
    function setTimelockYieldBoost(address newTimelockYieldBoost, uint256 vaultIdx) public onlyDelegateCall {
        AssetVaultEntry[5] storage assetVaults = _getAssetVaultEntries();
        assetVaults[vaultIdx].timelockYieldBoost = newTimelockYieldBoost;
    }

    /**
    * @notice Sets the netted positions
    * @param _nettedPositions A 2D array of the new netted positions
    */
    function setNettedPositions(
        int[5][5] memory _nettedPositions
    ) public onlyDelegateCall {
        _setNettedPositions(_nettedPositions);
    }

    /**
     * @notice Sets the keeper share config
     * @param _newKeeper The new keeper address
     * @param _newBps The new keeper share
     */
    function setKeeperShareConfig(address _newKeeper, uint _newBps) public onlyDelegateCall {
        require(_newKeeper != address(0), "Invalid keeper address");
        require(_newBps <= 5000, "More than max allowed");
        _getStorage().keeper = _newKeeper;
        _getStorage().keeperShareBps = _newBps;
    }

    /**
     * @notice Set the swap tolerance
     * @param _newSwapTolerance The new swap tolerance
     */
    function setSwapTolerance(uint _newSwapTolerance) public onlyDelegateCall {
        require(_newSwapTolerance <= 10000, "Invalid BPS");
        _getStorage().swapToleranceBps = _newSwapTolerance;
    }

    /**
    * @notice Settles internal Profit and Loss (PNL)
    * @param assetPrices An array of the asset prices
    * @param glpPrice The Global Liquidity Position (GLP) price
    */
    function settleInternalPnl(
        uint[5] memory assetPrices,
        uint glpPrice
    ) external onlyDelegateCall {
        _settleInternalPnl(assetPrices, glpPrice);
    }

    /**
    * @notice Sets the Global Liquidity Position (GLP) attribution for each vault
    * @param _newVals An array of the new GLP attributions
    */
    function setVaultGlpAttribution(
        uint[5] memory _newVals
    ) public onlyDelegateCall {
        uint[5] storage _vaultGlpAttribution = _getVaultGlpAttribution();
        for (uint i = 0; i < _vaultGlpAttribution.length; ++i) {
            _vaultGlpAttribution[i] = _newVals[i];
        }
    }

    /**
    * @notice Sets the netting price tolerance
    * @param _tolerance The new netting price tolerance
    */
    function setNettingPriceTolerance(
        uint _tolerance
    ) external onlyDelegateCall {
        require(_tolerance <= BIPS, "AggregateVaultHelper: tolerance too high");
        _getStorage().nettingPriceTolerance = _tolerance;
    }

    /**
    * @notice Sets the netting price tolerance
    * @param _tolerance The new netting price tolerance
    */
    function setGlpRebalanceTolerance(
        uint _tolerance
    ) external onlyDelegateCall {
        require(_tolerance <= BIPS, "AggregateVaultHelper: tolerance too high");
        _getStorage().glpRebalanceTolerance = _tolerance;
    }

    /**
    * @notice Sets the rebalance state
    * @param _rebalanceState A RebalanceState struct containing the new state
    */
    function setRebalanceState(
        RebalanceState memory _rebalanceState
    ) external onlyDelegateCall {
        RebalanceState storage rebalanceState = _getRebalanceState();
        rebalanceState.glpAllocation = _rebalanceState.glpAllocation;
        rebalanceState.glpComposition = _rebalanceState.glpComposition;
        rebalanceState.aggregatePositions = _rebalanceState.aggregatePositions;
        rebalanceState.epoch = _rebalanceState.epoch;

        for (uint i = 0; i < UMAMI_TOTAL_VAULTS; ++i) {
            for (uint j = 0; j < UMAMI_TOTAL_VAULTS; ++j) {
                rebalanceState.externalPositions[i][j] = _rebalanceState
                    .externalPositions[i][j];
                rebalanceState.adjustedExternalPositions[i][j] = _rebalanceState
                    .adjustedExternalPositions[i][j];
            }
        }
    }

    function setGlpMintBurnSlippageTolerance(uint _newTolerance) external onlyDelegateCall {
        _getStorage().glpMintBurnSlippageTolerance = _newTolerance;
    }

    /**
    * @notice Updates the netting checkpoint price for the specified epoch
    * @param assetPrices A NettedPrices struct containing the new asset prices
    * @param epochId The ID of the epoch
    */
    function updateNettingCheckpointPrice(
        INettedPositionTracker.NettedPrices memory assetPrices,
        uint epochId
    ) external onlyDelegateCall {
        _updateNettingCheckpointPrice(assetPrices, epochId);
    }

    /**
    * @notice Removes the position manager at the specified index
    * @param _addr The address of the position manager to remove
    * @param idx The index of the position manager in the position managers array
    */
    function removePositionManagerAt(
        address _addr,
        uint idx
    ) external onlyDelegateCall {
        IPositionManager[] storage positionManagers = _getPositionManagers();
        require(
            positionManagers[idx] == IPositionManager(_addr),
            "invalid idx"
        );
        positionManagers[idx] = positionManagers[positionManagers.length - 1];
        positionManagers.pop();
    }

    /**
    * @notice Updates the current epoch
    * @param _epoch The new epoch value
    */
    function updateEpoch(uint _epoch) public onlyDelegateCall {
        _getStorage().vaultState.epoch = _epoch;
    }

    // REBALANCE
    // ------------------------------------------------------------------------------------------

    /**
    * @notice Cycles the vaults with the given asset prices and GLP price, this settles internal position pnl,
    * and rebalances GLP held by each vault to the target amounts set in `openRebalancePeriod(...)`
    * @param assetPrices An array containing the asset prices
    * @param glpPrice The GLP price
    */
    function cycle(
        uint256[5] memory assetPrices,
        uint256 glpPrice
    ) external onlyDelegateCall {
        _cycle(assetPrices, glpPrice);
        VaultState storage vaultState = _getVaultState();
        emit Cycle(block.timestamp, vaultState.epoch);
    }

    /**
    * @notice Handle the GLP rewards according to the strategy. Claim esGMX + multiplier points and stake.
    * @param compound Indicates whether to compound the rewards or distribute them to the buffer
    */
    function handleGlpRewards(bool compound) public onlyDelegateCall {
        uint256 priorBalance = ERC20(TOKEN_WETH).balanceOf(address(this));
        _getFeeClaimRewardRouter().handleRewards(
            true,
            true,
            true,
            true,
            true,
            true,
            false
        );
        uint256 rewardAmount = ERC20(TOKEN_WETH).balanceOf(address(this)) -
            priorBalance;
        emit GlpRewardClaimed(rewardAmount);

        if (compound) {
            _compoundDistributeYield(rewardAmount);
        } else {
            _bufferDistributeYield(rewardAmount);
        }
    }

    /**
    * @notice Rebalances the GLP with the given next allocation and GLP price
    * @param _nextGlpAllocation An array containing the next GLP allocation
    * @param _glpPrice The GLP price
    */
    function rebalanceGlpPosition(
        uint[5] memory _nextGlpAllocation,
        uint _glpPrice
    ) external onlyDelegateCall {
        LibRebalance.rebalanceGlpPosition(_getStorage(), _nextGlpAllocation, _glpPrice);
    }

    // INTERNAL GETTERS
    // ------------------------------------------------------------------------------------------

    /**
    * @notice Get the AssetVaultEntry at the given index.
    * @param _idx The index of the AssetVaultEntry.
    * @return _assetVault The AssetVaultEntry at the given index.
    */
    function _getAssetVaultEntry(
        uint _idx
    ) internal view returns (AssetVaultEntry storage _assetVault) {
        _assetVault = _getAssetVaultEntries()[_idx];
    }

    /**
    * @notice Get the index of an AssetVaultEntry from a vault address.
    * @param _vault The vault address to find the index for.
    * @return _idx The index of the AssetVaultEntry with the given vault address.
    */
    function _getAssetVaultIdxFromVault(
        address _vault
    ) internal view returns (uint _idx) {
        AssetVaultEntry[5] storage assetVaults = _getAssetVaultEntries();

        for (uint i = 0; i < UMAMI_TOTAL_VAULTS; ++i) {
            if (assetVaults[i].vault == _vault) {
                return i;
            }
        }
        revert("AggregateVault: unknown asset vault");
    }

    /**
    * @notice Get the total value locked (TVL) for a specific AssetVaultEntry.
    * @param _assetVault The AssetVaultEntry to get the TVL for.
    * @return _totalTvl The total TVL for the AssetVaultEntry.
    * @return _bufferTvl The TVL held in the buffer for the AssetVaultEntry.
    * @return _glpTvl The TVL held in the glp for the AssetVaultEntry.
    * @return _hedgesTvl The TVL held in hedges for the AssetVaultEntry.
    */
    function _getAssetVaultTvl(
        AssetVaultEntry storage _assetVault
    )
        internal
        returns (uint _totalTvl, uint _bufferTvl, uint _glpTvl, uint _hedgesTvl)
    {
        uint assetVaultIdx = _getAssetVaultIdxFromVault(_assetVault.vault);

        _bufferTvl = ERC20(_assetVault.token).balanceOf(address(this));
        _glpTvl = _assetVaultGlpToken(assetVaultIdx);
        _hedgesTvl = _getAssetVaultHedgesInNativeToken(assetVaultIdx);
        _totalTvl = _bufferTvl + _glpTvl + _hedgesTvl;
    }

    /**
    * @notice Get the hedges value in USD for a specific vault index.
    * @param _vaultIdx The index of the vault to get the hedges value for.
    * @return _hedgesUsd The hedges value in USD for the specified vault index.
    */
    function _getAssetVaultHedgesInUsd(
        uint _vaultIdx
    ) internal returns (uint _hedgesUsd) {
        AssetVaultEntry[5] storage assetVaults = _getAssetVaultEntries();
        VaultState storage vaultState = _getVaultState();

        for (uint i = 1; i < UMAMI_TOTAL_VAULTS; ++i) {
            address token = assetVaults[i].token;
            uint totalNotional = _getTotalNotionalInExternalPositions(i);
            uint notional = vaultState.externalPositions[_vaultIdx][i] > 0
                ? uint(vaultState.externalPositions[_vaultIdx][i])
                : uint(-vaultState.externalPositions[_vaultIdx][i]);
            (uint totalMargin, ) = _getTotalMargin(token);

            if (totalNotional > 0)
                _hedgesUsd += (totalMargin * notional) / totalNotional;
        }
    }

    /**
    * @notice Get the hedges value in native token for a specific vault index.
    * @param _vaultIdx The index of the vault to get the hedges value for.
    * @return _hedgesToken The hedges value in native token for the specified vault index.
    */
    function _getAssetVaultHedgesInNativeToken(
        uint _vaultIdx
    ) internal returns (uint _hedgesToken) {
        uint hedgesUsd = _getAssetVaultHedgesInUsd(_vaultIdx);
        GlpHandler glpHandler = _getGlpHandler();
        AssetVaultEntry storage assetVault = _getAssetVaultEntries()[_vaultIdx];

        _hedgesToken = glpHandler.getUsdToToken(
            hedgesUsd,
            30,
            assetVault.token
        );
    }

    /**
    * @notice Get the total notional value in external positions for a specific index.
    * @param _idx The index to get the total notional value for.
    * @return _totalNotional The total notional value in external positions for the specified index.
    */
    function _getTotalNotionalInExternalPositions(
        uint _idx
    ) internal view returns (uint _totalNotional) {
        VaultState storage vaultState = _getVaultState();

        for (uint i = 0; i < UMAMI_TOTAL_VAULTS; ++i) {
            int externalPosition = vaultState.externalPositions[i][_idx];
            uint absoluteExternalPosition = externalPosition > 0
                ? uint(externalPosition)
                : uint(-externalPosition);
            _totalNotional += absoluteExternalPosition;
        }
    }

    /**
    * @notice Get the hedge attribution for all AssetVaults.
    * @return hedgeAttribution A two-dimensional array containing the hedge attribution for each AssetVault.
    */
    function _getAllAssetVaultsHedgeAtribution()
        external
        returns (uint[4][5] memory hedgeAttribution)
    {
        AssetVaultEntry[5] storage assetVaults = _getAssetVaultEntries();
        for (uint i = 0; i < assetVaults.length; ++i) {
            hedgeAttribution[i] = _getAssetVaultHedgeAttribution(assetVaults[i].vault);
        }
        return hedgeAttribution;
    }

    /**
    * @notice Get the total notional value for a specific token.
    * @param _token The address of the token to get the total notional value for.
    * @return _totalNotional The total notional value for the specified token.
    */
    function _getTotalNotional(
        address _token
    ) public returns (uint _totalNotional, bool _isLong) {
        IPositionManager[] storage positionManagers = _getPositionManagers();
        uint length = positionManagers.length;

        bool unset = true;
        _isLong = false;

        for (uint i = 0; i < length; ++i) {
            bytes memory ret = _delegatecall(
                address(positionManagers[i]),
                abi.encodeWithSignature("positionNotional(address)", _token)
            );
            (uint notional, bool isLong_) = abi.decode(ret, (uint, bool));
            if (notional > 0) {
                if (unset) {
                    _isLong = isLong_;
                    unset = false;
                } else {
                    require(_isLong == isLong_, "AggregateVaultHelper: mixed long/short");
                }
            }

            _totalNotional += notional;
        }
    }

    /**
    * @notice Get the total margin value for a specific token.
    * @param _token The address of the token to get the total margin value for.
    * @return _totalMargin The total margin value for the specified token.
    */
    function _getTotalMargin(
        address _token
    ) public returns (uint _totalMargin, bool _isLong) {
        IPositionManager[] storage positionManagers = _getPositionManagers();
        uint length = positionManagers.length;

        bool unset = true;
        _isLong = false;

        for (uint i = 0; i < length; ++i) {
            bytes memory ret = _delegatecall(
                address(positionManagers[i]),
                abi.encodeWithSignature("positionMargin(address)", _token)
            );
            (uint margin, bool isLong_) = abi.decode(ret, (uint, bool));
            if (margin > 0) {
                if (unset) {
                    _isLong = isLong_;
                    unset = false;
                } else {
                    require(
                        _isLong == isLong_,
                        "AggregateVaultHelper: mixed long/short"
                    );
                }
            }
            _totalMargin += margin;
        }
    }
    /**
    * @notice Returns the current prices from GMX.
    * @return _prices An INettedPositionTracker.NettedPrices struct containing the current asset prices
    */
    function _getCurrentPrices()
        public
        view
        returns (INettedPositionTracker.NettedPrices memory _prices)
    {
        _prices = LibAggregateVaultUtils.getCurrentPrices(_getStorage());
    }

    /**
    * @notice Calculates the hedge attribution for a given vault
    * @param _vault Address of the vault to calculate the hedge attribution for
    * @return _vaultMarginAttribution Array of hedge attributions for the given vault
    */
    function _getAssetVaultHedgeAttribution(
        address _vault
    ) internal returns (uint[4] memory _vaultMarginAttribution) {
        uint assetVaultIdx = _getAssetVaultIdxFromVault(_vault);
        AssetVaultEntry[5] storage assetVaults = _getAssetVaultEntries();
        VaultState storage vaultState = _getVaultState();
        for (uint i = 1; i < UMAMI_TOTAL_VAULTS; ++i) {
            address token = assetVaults[i].token;
            uint totalNotional = _getTotalNotionalInExternalPositions(i);
            uint notional = vaultState.externalPositions[assetVaultIdx][i] > 0
                ? uint(vaultState.externalPositions[assetVaultIdx][i])
                : uint(-vaultState.externalPositions[assetVaultIdx][i]);
            (uint actualNotional, ) = _getTotalNotional(token);

            if (totalNotional > 0) {
                _vaultMarginAttribution[i - 1] =
                    (actualNotional * notional) /
                    totalNotional;
            }
        }
        return _vaultMarginAttribution;
    }

    // INTERNAL REBALACE LOGIC
    // ------------------------------------------------------------------------------------------

    /**
    * @notice Updates the netting checkpoint price for a given epoch
    * @param assetPrices The asset prices to update the checkpoint with
    * @param epochId The ID of the epoch to update the checkpoint for
    */
    function _updateNettingCheckpointPrice(
        INettedPositionTracker.NettedPrices memory assetPrices,
        uint256 epochId
    ) internal {
        // uninitialized case
        INettedPositionTracker.NettedPrices
            storage nettedPrice = _getEpochNettedPrice(epochId);
        require(
            nettedPrice.stable == 0,
            "AggregateVault: lastNettedPrices already inited for given epoch"
        );
        _checkNettingCheckpointPrice(assetPrices);
        mapping(uint => INettedPositionTracker.NettedPrices)
            storage lastNettedPrices = _getLastNettedPrices();
        lastNettedPrices[epochId] = assetPrices;
        emit UpdateNettingCheckpointPrice(lastNettedPrices[epochId-1], assetPrices);
    }

    /**
    * @notice Cycles through the rebalancing process with the given asset prices and GLP price.
    * @dev netting checkpoint price is set to 0 after settling internal pnl.
    * @param assetPrices An array of the current asset prices
    * @param glpPrice The current GLP price
    */
    function _cycle(
        uint256[5] memory assetPrices,
        uint256 glpPrice
    ) internal {
        // settle internal netted pnl only after first round
        VaultState storage vaultState = _getVaultState();
        if (vaultState.epoch > 0) {
            _settleInternalPnl(assetPrices, glpPrice);
        }
        // update next netting prices
        _updateNettingCheckpointPrice(
            INettedPositionTracker.NettedPrices({
                stable: assetPrices[0],
                eth: assetPrices[1],
                btc: assetPrices[2],
                link: assetPrices[3],
                uni: assetPrices[4]
            }),
            vaultState.epoch + 1
        );

        // note internal pnl is reset to zero at this point
        RebalanceState storage rebalanceState = _getRebalanceState();
        // rebalance glp
        LibRebalance.rebalanceGlpPosition(_getStorage(), rebalanceState.glpAllocation, glpPrice);
    }

    /**
    * @notice Settles the internal PnL for the given asset prices and GLP price
    * @param assetPrices An array of the current asset prices
    * @param glpPrice The current GLP price
    */
    function _settleInternalPnl(
        uint256[5] memory assetPrices,
        uint256 glpPrice
    ) internal {
        uint256[5] memory settledVaultGlpAmount;
        int256[5] memory nettedPnl;
        int256[5] memory glpPnl;
        int256[5] memory percentPriceChange;

        INettedPositionTracker.NettedPrices
            memory nettedPrices = INettedPositionTracker.NettedPrices({
                stable: assetPrices[0],
                eth: assetPrices[1],
                btc: assetPrices[2],
                link: assetPrices[3],
                uni: assetPrices[4]
            });

        VaultState storage vaultState = _getVaultState();
        // get the previous allocated glp amount
        uint[5] memory vaultGlpAmount = LibAggregateVaultUtils.getVaultsGlpNoPnl(_getStorage());
        (settledVaultGlpAmount, nettedPnl, glpPnl, percentPriceChange) = _getNettedPositionTracker()
            .settleNettingPositionPnl(
                _getNettedPositions(),
                nettedPrices,
                _getEpochNettedPrice(vaultState.epoch),
                vaultGlpAmount,
                glpPrice,
                _getZeroSumPnlThreshold()
            );
        // note set the updated proportions?
        setVaultGlpAttribution(settledVaultGlpAmount);
        emit SettleNettedPositionPnl(vaultGlpAmount, settledVaultGlpAmount, glpPnl, nettedPnl, percentPriceChange);
    }

    // INTERNAL GLP POSITION MANAGMENT
    // ------------------------------------------------------------------------------------------

    /**
     * @notice Swaps eth yield into the buffer for each vault.
     */
    function _bufferDistributeYield(uint256 _rewardAmount) internal {
        require(_rewardAmount > 0, "AggregateVault: _rewardAmount 0");
        AssetVaultEntry[5] storage assetVaults = _getAssetVaultEntries();
        uint swapInput;
        GlpHandler handler = _getGlpHandler();
        for (uint256 i = 0; i < assetVaults.length; i++) {
            if (assetVaults[i].token != TOKEN_WETH) {
                swapInput = _rewardAmount * _getVaultGlpAttributeProportion(i) / 1e18;
                PositionManagerRouter(payable(address(this))).executeSwap(
                    _getUniV3SwapManager(),
                    TOKEN_WETH,
                    assetVaults[i].token,
                    swapInput,
                    handler.tokenToToken(
                        TOKEN_WETH,
                        assetVaults[i].token,
                        swapInput),
                    bytes("") // UniV3SwapManager not required
                );
            }
        }
    }

    /**
     * @notice Compounds yield into GLP and distributes it to vaults based on TVL using pro-rata method.
     */
    function _compoundDistributeYield(uint256 _rewardAmount) internal {
        if (_rewardAmount > 0) {
            ERC20(TOKEN_WETH).safeApprove(GMX_GLP_MANAGER, _rewardAmount);
            uint256 amountWithSlippage = VaultMath.getSlippageAdjustedAmount(
                _rewardAmount,
                _getStorage().glpMintBurnSlippageTolerance
            );
            uint256 glpMinted = IRewardRouterV2(GMX_GLP_REWARD_ROUTER)
                .mintAndStakeGlp(
                    TOKEN_WETH,
                    _rewardAmount,
                    amountWithSlippage,
                    0
                );
            AssetVaultEntry[5] storage assetVaults = _getAssetVaultEntries();
            uint[5] storage _vaultGlpAttribution = _getVaultGlpAttribution();

            uint[5] memory increments;
            for (uint256 i = 0; i < assetVaults.length; i++) {
                increments[i] =
                    (glpMinted * _getVaultGlpAttributeProportion(i)) /
                    1e18;
            }

            for (uint256 i = 0; i < assetVaults.length; i++) {
                _vaultGlpAttribution[i] += increments[i];
            }
            emit CompoundDistributeYield(increments);
        }
    }

    // INTERNAL GLP LOGIC
    // ------------------------------------------------------------------------------------------

    /**
    * @notice Calculates the GLP token amount owned by a vault.
    * @param _vaultIdx The index of the vault.
    * @return _glpToken The amount of GLP token owned by the vault.
    */
    function _assetVaultGlpToken(
        uint _vaultIdx
    ) internal view returns (uint _glpToken) {
        uint currentEpoch = _getVaultState().epoch;
        uint vaultGlp = LibAggregateVaultUtils.getVaultGlp(_getStorage(), _vaultIdx, currentEpoch);
        AssetVaultEntry storage assetVault = _getAssetVaultEntries()[_vaultIdx];
        GlpHandler glpHandler = _getGlpHandler();
        _glpToken = glpHandler.previewGlpMintBurn(assetVault.token, vaultGlp);
    }

    /**
    * @notice Calculates the proportion of GLP attributed to a vault. 100% = 1e18, 10% = 0.1e18.
    * @param _vaultIdx The index of the vault.
    * @return _proportion The proportion of GLP attributed to the vault.
    */
    function _getVaultGlpAttributeProportion(
        uint _vaultIdx
    ) internal view returns (uint _proportion) {
        uint[5] memory _vaultGlpAttribution = _getVaultGlpAttribution();
        uint totalGlpAttribution = Solarray.arraySum(_vaultGlpAttribution);
        if (totalGlpAttribution == 0) return 0;
        return (_vaultGlpAttribution[_vaultIdx] * 1e18) / totalGlpAttribution;
    }

    // UTILS
    // ------------------------------------------------------------------------------------------

    /**
    * @notice Resets the checkpoint prices for the given number of epochs.
    * @param _noOfEpochs The number of epochs to reset checkpoint prices for.
    */
    function resetCheckpointPrices(uint _noOfEpochs) public onlyDelegateCall {
        INettedPositionTracker.NettedPrices
            memory assetPrices = INettedPositionTracker.NettedPrices({
                stable: 0,
                eth: 0,
                btc: 0,
                link: 0,
                uni: 0
            });
        mapping(uint => INettedPositionTracker.NettedPrices)
            storage lastNettedPrices = _getLastNettedPrices();
        for (uint i = 0; i < _noOfEpochs; ++i) {
            lastNettedPrices[i] = assetPrices;
        }
    }

    /**
    * @notice Checks if the netting checkpoint prices are within the tolerance of the current prices.
    * @dev check netting prices from keeper are ~= current prices.
    * @param _assetPrices The netting checkpoint asset prices.
    */
    function _checkNettingCheckpointPrice(
        INettedPositionTracker.NettedPrices memory _assetPrices
    ) internal view {
        INettedPositionTracker.NettedPrices
            memory currentPrices = LibAggregateVaultUtils.getCurrentPrices(_getStorage());
        uint tolerance = _getNettingPriceTolerance();
        _assertWithinTolerance(
            _assetPrices.stable,
            currentPrices.stable,
            tolerance
        );
        _assertWithinTolerance(_assetPrices.eth, currentPrices.eth, tolerance);
        _assertWithinTolerance(_assetPrices.btc, currentPrices.btc, tolerance);
        _assertWithinTolerance(
            _assetPrices.link,
            currentPrices.link,
            tolerance
        );
        _assertWithinTolerance(_assetPrices.uni, currentPrices.uni, tolerance);
    }

    /**
    * @notice Asserts that the actual value is within the tolerance range of the target value.
    * @param _actual The actual value.
    * @param _target The target value.
    * @param _toleranceBps The tolerance in basis points (1 basis point = 0.01%).
    */
    function _assertWithinTolerance(
        uint _actual,
        uint _target,
        uint _toleranceBps
    ) internal pure {
        require(_toleranceBps <= BIPS, "tolerance must be <= 100%");
        uint lower = (_target * (BIPS - _toleranceBps)) / BIPS;
        uint higher = (_target * (BIPS + _toleranceBps)) / BIPS;
        require(_actual >= lower && _actual <= higher, "not within tolerance");
    }

    /**
    * @notice Executes a delegate call to the specified target with the given data.
    * @param _target The target address to delegate call.
    * @param _data The data to be sent as part of the delegate call.
    * @return ret The returned data from the delegate call.
    */
    function _delegatecall(
        address _target,
        bytes memory _data
    ) internal returns (bytes memory ret) {
        bool success;
        (success, ret) = _target.delegatecall(_data);
        if (!success) {
            /// @solidity memory-safe-assembly
            assembly {
                let length := mload(ret)
                let start := add(ret, 0x20)
                revert(start, length)
            }
        }
        return ret;
    }

    /**
    * @notice Returns an empty array of bytes4 signatures.
    * @return _ret An empty array of bytes4 signatures.
    */
    function callbackSigs() external pure returns (bytes4[] memory _ret) {
        _ret = new bytes4[](0);
    }
}

