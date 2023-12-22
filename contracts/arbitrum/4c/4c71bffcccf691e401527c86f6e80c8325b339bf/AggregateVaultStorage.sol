// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import {Whitelist} from "./Whitelist.sol";
import {NettingMath} from "./NettingMath.sol";
import {IGlpRebalanceRouter} from "./IGlpRebalanceRouter.sol";
import {INettedPositionTracker} from "./INettedPositionTracker.sol";
import {IVaultFeesAndHooks} from "./IVaultFeesAndHooks.sol";
import {GlpHandler} from "./GlpHandler.sol";
import {IPositionManager} from "./IPositionManager.sol";
import {IRewardRouterV2} from "./IRewardRouterV2.sol";
import {UMAMI_TOTAL_VAULTS} from "./constants.sol";
import {ISwapManager} from "./ISwapManager.sol";

/// @title AggregateVaultStorage
/// @author Umami DAO
/// @notice Storage inheritance for AggregateVault 
abstract contract AggregateVaultStorage {

    bytes32 public constant STORAGE_SLOT = keccak256("AggregateVault.storage");

    struct AssetVaultEntry {
        address vault;
        address token;
        uint256 feeWatermarkPPS;
        uint256 feeWatermarkDate;
        int256 epochDelta;
        uint256 lastCheckpointTvl;
        address timelockYieldBoost;
    }

    struct VaultState {
        uint256 epoch;
        bool rebalanceOpen;
        uint256 lastRebalanceTime;
        uint256[5] glpAllocation;
        int[5] aggregatePositions;
        int[5][5] externalPositions;
        address feeRecipient;
        address depositFeeEscrow;
        address withdrawalFeeEscrow;
        uint256[5] vaultCaps;
        uint256[5] rebalancePPS;
    }

    struct RebalanceState {
        uint256[5] glpAllocation;
        uint256[5] glpComposition;
        int256[5][5] externalPositions;
        int256[5] aggregatePositions;
        uint256 epoch;
        int256[5][5] adjustedExternalPositions;
    }

    struct VaultFees {
        uint256 performanceFee;
        uint256 managementFee;
        uint256 withdrawalFee;
        uint256 depositFee;
        uint256 timelockBoostAmount;
    }

    /// @dev Fees are 18-decimal places. For example: 20 * 10**18 = 20%
    struct VaultFeeParams {
        uint256 performanceFeePercent;
        uint256 managementFeePercent;
        uint256 withdrawalFeePercent;
        uint256 depositFeePercent;
    }

    struct AVStorage {
        /// @notice The array of asset vault entries.
        AssetVaultEntry[5] assetVaults;
        /// @notice The mapping of token addresses to asset vault indices.
        mapping(address => uint) tokenToAssetVaultIndex;
        /// @notice The mapping of vault indices to asset vault indices.
        mapping(address => uint) vaultToAssetVaultIndex;
        /// @notice The address of the GLP reward claim contract.
        address glpRewardClaimAddr;
        /// @notice The current vault state.
        VaultState vaultState;
        /// @notice The current rebalance state.
        RebalanceState rebalanceState;
        /// @notice The vault fees structure.
        VaultFees vaultFees;
        /// @notice Stores the amount of GLP attributed to each vault.
        uint256[5] vaultGlpAttribution;
        /// @notice Contract library used for routing GLP rebalance.
        IGlpRebalanceRouter glpRebalanceRouter;
        /// @notice The netted position tracker contract.
        INettedPositionTracker nettedPositionTracker;
        /// @notice The fee & hook helper contract.
        address feeAndHookHelper;
        /// @notice Maps epoch IDs to the last netted prices.
        mapping(uint256 => INettedPositionTracker.NettedPrices) lastNettedPrices;
        /// @notice The GLP handler contract.
        GlpHandler glpHandler;
        /// @notice The array of position manager contracts.
        IPositionManager[] positionManagers;
        /// @notice Flag to indicate whether netting should be checked.
        bool shouldCheckNetting;
        /// @notice The whitelist contract.
        Whitelist whitelist;
        /// @notice The address of the aggregate vault helper contract.
        address aggregateVaultHelper;
        /// @notice The array of active aggregate positions.
        int256[4] activeAggregatePositions;
        /// @notice The matrix of netted positions.
        int256[5][5] nettedPositions;
        /// @notice The matrix of active external positions.
        int256[5][5] activeExternalPositions;
        /// @notice The last GLP composition array.
        uint256[5] lastGlpComposition;
        /// @notice The netting math contract.
        NettingMath nettingMath;
        /// @notice The netted threshold value.
        uint256 nettedThreshold;
        /// @notice The netting price tolerance value.
        uint256 nettingPriceTolerance;
        /// @notice Glp rebalance tollerance.
        uint256 glpRebalanceTolerance;
        /// @notice The zero sum PnL threshold value.
        uint256 zeroSumPnlThreshold;
        /// @notice The Uniswap V3 swap manager contract.
        ISwapManager uniV3SwapManager;
        /// @notice Slippage tolerance on glp mints and burns.
        uint256 glpMintBurnSlippageTolerance;
        /// @notice The helper contract for vault hooks.
        address hookHelper;
        /// @notice BPS of the deposit and withdraw fees that go to the keeper.
        uint keeperShareBps;
        /// @notice keeper address that gets the deposit and withdraw fees' share.
        address keeper;
        /// @notice swap tolerance bps
        uint256 swapToleranceBps;
    }

    /**
    * @dev Retrieves the storage struct of the contract.
    * @return _storage The storage struct containing all contract state variables.
    */
    function _getStorage() internal pure returns (AVStorage storage _storage) {
        bytes32 slot = STORAGE_SLOT;

        assembly {
            _storage.slot := slot
        }
    }

    /**
    * @dev Retrieves the current rebalance state from storage.
    * @return _rebalanceState The current rebalance state.
    */
    function _getRebalanceState()
        internal
        view
        returns (RebalanceState storage _rebalanceState)
    {
        _rebalanceState = _getStorage().rebalanceState;
    }

    /**
    * @dev Retrieves the asset vault entries array from storage.
    * @return _assetVaults The array of asset vault entries.
    */
    function _getAssetVaultEntries()
        internal
        view
        returns (AssetVaultEntry[5] storage _assetVaults)
    {
        _assetVaults = _getStorage().assetVaults;
    }

    /**
    * @dev Retrieves the vault state from storage.
    * @return _vaultState The current vault state.
    */
    function _getVaultState()
        internal
        view
        returns (VaultState storage _vaultState)
    {
        _vaultState = _getStorage().vaultState;
    }

    /**
    * @dev Retrieves the array of position managers from storage.
    * @return _positionManagers The array of position managers.
    */
    function _getPositionManagers()
        internal
        view
        returns (IPositionManager[] storage _positionManagers)
    {
        _positionManagers = _getStorage().positionManagers;
    }

    /**
    * @dev Retrieves the array of position managers from storage.
    * @return _glpHandler The array of position managers.
    */
    function _getGlpHandler() internal view returns (GlpHandler _glpHandler) {
        _glpHandler = _getStorage().glpHandler;
    }

    /**
    * @dev Retrieves the vault to asset vault index mapping from storage.
    * @return _vaultToAssetVaultIndex The mapping of vault addresses to asset vault indexes.
    */
    function _getVaultToAssetVaultIndex()
        internal
        view
        returns (mapping(address => uint) storage _vaultToAssetVaultIndex)
    {
        _vaultToAssetVaultIndex = _getStorage().vaultToAssetVaultIndex;
    }

    /**
    * @dev Retrieves the fee claim reward router from storage.
    * @return _rewardRouter The current reward router.
    */
    function _getFeeClaimRewardRouter()
        internal
        view
        returns (IRewardRouterV2 _rewardRouter)
    {
        _rewardRouter = IRewardRouterV2(_getStorage().glpRewardClaimAddr);
    }

    /**
    * @dev Retrieves the vault GLP attribution array from storage.
    * @return _vaultGlpAttribution The array of vault GLP attributions.
    */
    function _getVaultGlpAttribution()
        internal
        view
        returns (uint[5] storage _vaultGlpAttribution)
    {
        _vaultGlpAttribution = _getStorage().vaultGlpAttribution;
    }

    /**
    * @dev Retrieves the netted positions matrix from storage.
    * @return _nettedPositions The matrix of netted positions.
    */
    function _getNettedPositions()
        internal
        view
        returns (int256[5][5] storage _nettedPositions)
    {
        _nettedPositions = _getStorage().nettedPositions;
    }

    /**
    * @dev Retrieves the rebalance router from storage.
    * @return _rebalanceRouter The current rebalance router.
    */
    function _getRebalanceRouter()
        internal
        view
        returns (IGlpRebalanceRouter _rebalanceRouter)
    {
        _rebalanceRouter = _getStorage().glpRebalanceRouter;
    }

    /**
    * @dev Retrieves the netted position tracker from storage.
    * @return _nettedPositionTracker The current netted position tracker.
    */
    function _getNettedPositionTracker()
        internal
        view
        returns (INettedPositionTracker _nettedPositionTracker)
    {
        _nettedPositionTracker = _getStorage().nettedPositionTracker;
    }

    /**
    * @dev Retrieves the last netted prices mapping from storage.
    * @return _lastNettedPrices The mapping of epochs to netted prices.
    */
    function _getLastNettedPrices()
        internal
        view
        returns (
            mapping(uint256 => INettedPositionTracker.NettedPrices)
                storage _lastNettedPrices
        )
    {
        _lastNettedPrices = _getStorage().lastNettedPrices;
    }

    /**
    * @dev Retrieves the netted prices for a given epoch from storage.
    * @param _epoch The epoch number to get the netted prices for.
    * @return _nettedPrices The netted prices for the given epoch.
    */
    function _getEpochNettedPrice(
        uint _epoch
    )
        internal
        view
        returns (INettedPositionTracker.NettedPrices storage _nettedPrices)
    {
        _nettedPrices = _getLastNettedPrices()[_epoch];
    }

    /**
    * @dev Retrieves the fee and hook helper from storage.
    * @return _feeAndHookHelper The current fee & hook helper.
    */
    function _getFeeHookHelper()
        internal
        view
        returns (address _feeAndHookHelper)
    {
        _feeAndHookHelper = _getStorage().feeAndHookHelper;
    }

    /**
    * @dev Retrieves the vault fees struct from storage.
    * @return _vaultFees The current vault fees.
    */
    function _getVaultFees()
        internal
        view
        returns (VaultFees storage _vaultFees)
    {
        _vaultFees = _getStorage().vaultFees;
    }

    /**
    * @dev Retrieves the token to asset vault index mapping from storage.
    * @return _tokenToAssetVaultIndex The mapping of token addresses to asset vault indexes.
    */
    function _getTokenToAssetVaultIndex()
        internal
        view
        returns (mapping(address => uint) storage _tokenToAssetVaultIndex)
    {
        _tokenToAssetVaultIndex = _getStorage().tokenToAssetVaultIndex;
    }

    /**
    * @dev Retrieves the whitelist from storage.
    * @return _whitelist The current whitelist.
    */
    function _getWhitelist() internal view returns (Whitelist _whitelist) {
        _whitelist = _getStorage().whitelist;
    }

    /**
    * @dev Retrieves the netting math from storage.
    * @return _nettingMath The current netting math.
    */
    function _getNettingMath() internal view returns (NettingMath _nettingMath) {
        _nettingMath = _getStorage().nettingMath;
    }

    /**
    * @dev Retrieves the aggregate vault helper from storage.
    * @return _aggregateVaultHelper The current aggregate vault helper address.
    */
    function _getAggregateVaultHelper()
        internal
        view
        returns (address _aggregateVaultHelper)
    {
        _aggregateVaultHelper = _getStorage().aggregateVaultHelper;
    }

    /**
    * @dev Retrieves the netted threshold from storage.
    * @return _nettedThreshold The current netted threshold value.
    */
    function _getNettedThreshold()
        internal
        view
        returns (uint256 _nettedThreshold)
    {
        _nettedThreshold = _getStorage().nettedThreshold;
    }

    /**
    * @dev Sets the netted positions matrix in storage.
    * @param _nettedPositions The updated netted positions matrix.
    */
    function _setNettedPositions(int[5][5] memory _nettedPositions) internal {
        int[5][5] storage nettedPositions = _getNettedPositions();
        for (uint i = 0; i < 5; ++i) {
            for (uint j = 0; j < 5; ++j) {
                nettedPositions[i][j] = _nettedPositions[i][j];
            }
        }
    }

    /**
    * @dev Sets the vault GLP attribution array in storage.
    * @param _vaultGlpAttribution The updated vault GLP attribution array.
    */
    function _setVaultGlpAttribution(
        uint[5] memory _vaultGlpAttribution
    ) internal {
        uint[5] storage __vaultGlpAttribution = _getVaultGlpAttribution();
        for (uint i = 0; i < 5; ++i) {
            __vaultGlpAttribution[i] = _vaultGlpAttribution[i];
        }
    }

    /**
    * @dev Retrieves the asset vault entry for the given asset address.
    * @param _asset The asset address for which to retrieve the vault entry.
    * @return vault The asset vault entry for the given asset address.
    */
    function getVaultFromAsset(address _asset) public view returns (AssetVaultEntry memory vault) {
        AssetVaultEntry[5] storage assetVaults = _getAssetVaultEntries();
        for (uint i = 0; i < 5; i++) {
            if (assetVaults[i].token == _asset) {
                return assetVaults[i];
            }
        }
        return vault;
    }

    /**
    * @dev Retrieves the netting price tolerance from storage.
    * @return _tolerance The current netting price tolerance value.
    */
    function _getNettingPriceTolerance()
        internal
        view
        returns (uint _tolerance)
    {
        _tolerance = _getStorage().nettingPriceTolerance;
    }

    /**
    * @dev Retrieves the zero sum PnL threshold from storage.
    * @return _zeroSumPnlThreshold The current zero sum PnL threshold value.
    */
    function _getZeroSumPnlThreshold()
        internal
        view
        returns (uint256 _zeroSumPnlThreshold)
    {
        _zeroSumPnlThreshold = _getStorage().zeroSumPnlThreshold;
    }

    /**
    * @dev Updates the external positions in the vault state based on the given rebalance storage.
    * @param _rebalanceStorage The rebalance storage containing the updated external positions.
    */
    function _setStateExternalPositions(
        RebalanceState storage _rebalanceStorage
    ) internal {
        VaultState storage vaultState = _getVaultState();
        for (uint i = 0; i < UMAMI_TOTAL_VAULTS; ++i) {
            for (uint j = 0; j < UMAMI_TOTAL_VAULTS; ++j) {
                vaultState.externalPositions[i][j] = _rebalanceStorage
                    .adjustedExternalPositions[i][j];
            }
        }
    }

    /**
    * @dev Retrieves the Uniswap V3 swap manager from storage.
    * @return _swapManager The current Uniswap V3 swap manager.
    */
    function _getUniV3SwapManager()
        internal
        view
        returns (ISwapManager _swapManager)
    {
        _swapManager = _getStorage().uniV3SwapManager;
    }
}

