//SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.19;

import "./IUniswapV3Pool.sol";
import "./IUniswapV3MintCallback.sol";
import "./IUniswapV3SwapCallback.sol";
import {TransferHelper} from "./TransferHelper.sol";
import "./FixedPointMathLib.sol";
import {Initializable} from "./Initializable.sol";
import "./ReentrancyGuard.sol";
import "./DataType.sol";
import "./VaultLib.sol";
import "./PositionCalculator.sol";
import "./Perp.sol";
import "./ScaledAsset.sol";
import "./SwapLib.sol";
import "./InterestRateModel.sol";
import "./ApplyInterestLib.sol";
import "./AddPairLogic.sol";
import "./LiquidationLogic.sol";
import "./ReaderLogic.sol";
import "./SupplyLogic.sol";
import "./TradePerpLogic.sol";
import "./UpdateMarginLogic.sol";
import "./ReallocationLogic.sol";
import "./IController.sol";

/**
 * Error Codes
 * C0: invalid asset rist parameters
 * C1: caller must be operator
 * C2: caller must be vault owner
 * C3: token0 or token1 must be registered stable token
 * C4: invalid interest rate model parameters
 * C5: invalid vault creation
 */
contract Controller is Initializable, ReentrancyGuard, IUniswapV3MintCallback, IUniswapV3SwapCallback, IController {
    DataType.GlobalData public globalData;

    address public operator;

    address public liquidator;

    mapping(address => bool) public allowedUniswapPools;

    event OperatorUpdated(address operator);
    event LiquidatorUpdated(address liquidator);

    modifier onlyOperator() {
        require(operator == msg.sender, "C1");
        _;
    }

    constructor() {}

    /**
     * @dev Callback for Uniswap V3 pool.
     */
    function uniswapV3MintCallback(uint256 amount0, uint256 amount1, bytes calldata) external override {
        require(allowedUniswapPools[msg.sender]);
        IUniswapV3Pool uniswapPool = IUniswapV3Pool(msg.sender);
        if (amount0 > 0) {
            TransferHelper.safeTransfer(uniswapPool.token0(), msg.sender, amount0);
        }
        if (amount1 > 0) {
            TransferHelper.safeTransfer(uniswapPool.token1(), msg.sender, amount1);
        }
    }

    /**
     * @dev Callback for Uniswap V3 pool.
     */
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata) external override {
        require(allowedUniswapPools[msg.sender]);
        IUniswapV3Pool uniswapPool = IUniswapV3Pool(msg.sender);
        if (amount0Delta > 0) {
            TransferHelper.safeTransfer(uniswapPool.token0(), msg.sender, uint256(amount0Delta));
        }
        if (amount1Delta > 0) {
            TransferHelper.safeTransfer(uniswapPool.token1(), msg.sender, uint256(amount1Delta));
        }
    }

    function initialize() public initializer {
        operator = msg.sender;

        AddPairLogic.initializeGlobalData(globalData);
    }

    function vaultCount() external view returns (uint256) {
        return globalData.vaultCount;
    }

    /**
     * @notice Sets new operator
     * @dev Only operator can call this function.
     * @param _newOperator The address of new operator
     */
    function setOperator(address _newOperator) external onlyOperator {
        require(_newOperator != address(0));
        operator = _newOperator;

        emit OperatorUpdated(_newOperator);
    }

    /**
     * @notice Sets new liquidator
     * @dev Only operator can call this function.
     * @param _newLiquidator The address of new operator
     */
    function setLiquidator(address _newLiquidator) external onlyOperator {
        require(_newLiquidator != address(0));
        liquidator = _newLiquidator;

        emit LiquidatorUpdated(_newLiquidator);
    }

    /**
     * @notice Adds an pair group
     * @param _stableAssetAddress The address of stable asset
     * @param _marginRounder Margin rounder
     * @return pairGroupId Pair group id
     */
    function addPairGroup(address _stableAssetAddress, uint8 _marginRounder) external onlyOperator returns (uint256) {
        return AddPairLogic.addPairGroup(globalData, _stableAssetAddress, _marginRounder);
    }

    /**
     * @notice Adds token pair to the contract
     * @dev Only operator can call this function.
     * @param _addPairParam parameters to define asset risk and interest rate model
     * @return pairId The id of pair
     */
    function addPair(DataType.AddPairParams memory _addPairParam) external onlyOperator returns (uint256) {
        return AddPairLogic.addPair(globalData, allowedUniswapPools, _addPairParam);
    }

    /**
     * @notice Updates asset risk parameters.
     * @dev The function can be called by operator.
     * @param _pairId The id of asset to update params.
     * @param _riskParams Asset risk parameters.
     */
    function updateAssetRiskParams(uint256 _pairId, DataType.AssetRiskParams memory _riskParams)
        external
        onlyOperator
    {
        AddPairLogic.updateAssetRiskParams(globalData.pairs[_pairId], _riskParams);
    }

    /**
     * @notice Updates interest rate model parameters.
     * @dev The function can be called by operator.
     * @param _pairId The id of pair to update params.
     * @param _stableIrmParams Asset interest-rate parameters for stable.
     * @param _underlyingIrmParams Asset interest-rate parameters for underlying.
     */
    function updateIRMParams(
        uint256 _pairId,
        InterestRateModel.IRMParams memory _stableIrmParams,
        InterestRateModel.IRMParams memory _underlyingIrmParams
    ) external onlyOperator {
        AddPairLogic.updateIRMParams(globalData.pairs[_pairId], _stableIrmParams, _underlyingIrmParams);
    }

    /**
     * @notice Reallocates range of Uniswap LP position.
     * @param _pairId The id of pair to reallocate.
     */
    function reallocate(uint256 _pairId) external returns (bool, int256) {
        return ReallocationLogic.reallocate(globalData, _pairId);
    }

    /**
     * @notice Supplys token and mints claim token
     * @param _pairId The id of pair being supplied to the pool
     * @param _amount The amount of asset being supplied
     * @param _isStable If true supplys to stable pool, if false supplys to underlying pool
     * @return finalMintAmount The amount of claim token being minted
     */
    function supplyToken(uint256 _pairId, uint256 _amount, bool _isStable)
        external
        nonReentrant
        returns (uint256 finalMintAmount)
    {
        return SupplyLogic.supply(globalData, _pairId, _amount, _isStable);
    }

    /**
     * @notice Withdraws token and burns claim token
     * @param _pairId The id of pair being withdrawn from the pool
     * @param _amount The amount of asset being withdrawn
     * @param _isStable If true supplys to stable pool, if false supplys to underlying pool
     * @return finalBurnAmount The amount of claim token being burned
     * @return finalWithdrawAmount The amount of token being withdrawn
     */
    function withdrawToken(uint256 _pairId, uint256 _amount, bool _isStable)
        external
        nonReentrant
        returns (uint256 finalBurnAmount, uint256 finalWithdrawAmount)
    {
        return SupplyLogic.withdraw(globalData, _pairId, _amount, _isStable);
    }

    /**
     * @notice Deposit or withdraw margin
     * @param _pairGroupId The id of pair group
     * @param _marginAmount The amount of margin. Positive means deposit and negative means withdraw.
     * @return vaultId The id of vault created
     */
    function updateMargin(uint64 _pairGroupId, int256 _marginAmount)
        external
        override(IController)
        nonReentrant
        returns (uint256 vaultId)
    {
        return UpdateMarginLogic.updateMargin(globalData, _pairGroupId, _marginAmount);
    }

    /**
     * @notice Deposit margin to the isolated vault or withdraw margin from the isolated vault.
     * @param _pairGroupId The id of pair group
     * @param _isolatedVaultId The id of an isolated vault
     * @param _marginAmount The amount of margin. Positive means deposit and negative means withdraw.
     * @param _moveFromMainVault If true margin is moved from the main vault, if false the margin is transfered from the account.
     * @return isolatedVaultId The id of vault created
     */
    function updateMarginOfIsolated(
        uint64 _pairGroupId,
        uint256 _isolatedVaultId,
        int256 _marginAmount,
        bool _moveFromMainVault
    ) external override(IController) nonReentrant returns (uint256 isolatedVaultId) {
        return UpdateMarginLogic.updateMarginOfIsolated(
            globalData, _pairGroupId, _isolatedVaultId, _marginAmount, _moveFromMainVault
        );
    }

    function openIsolatedPosition(
        uint256 _vaultId,
        uint64 _pairId,
        TradePerpLogic.TradeParams memory _tradeParams,
        uint256 _depositAmount,
        bool _revertOnDupPair
    ) external nonReentrant returns (uint256 isolatedVaultId, DataType.TradeResult memory tradeResult) {
        uint256 pairGroupId = globalData.pairs[_pairId].pairGroupId;

        // check duplication
        require(
            !_revertOnDupPair
                || !VaultLib.getDoesExistsPairId(globalData, globalData.ownVaultsMap[msg.sender][pairGroupId], _pairId),
            "DUP_PAIR"
        );

        if (_depositAmount > 0) {
            isolatedVaultId = UpdateMarginLogic.updateMarginOfIsolated(
                globalData, pairGroupId, _vaultId, SafeCast.toInt256(_depositAmount), true
            );
        } else {
            isolatedVaultId = _vaultId;
        }

        tradeResult = TradePerpLogic.execTrade(globalData, isolatedVaultId, _pairId, _tradeParams);
    }

    function closeIsolatedPosition(
        uint256 _vaultId,
        uint64 _pairId,
        TradePerpLogic.TradeParams memory _tradeParams,
        uint256 _withdrawAmount
    ) external nonReentrant returns (DataType.TradeResult memory tradeResult) {
        uint256 pairGroupId = globalData.pairs[_pairId].pairGroupId;

        tradeResult = TradePerpLogic.execTrade(globalData, _vaultId, _pairId, _tradeParams);

        UpdateMarginLogic.updateMarginOfIsolated(
            globalData, pairGroupId, _vaultId, -SafeCast.toInt256(_withdrawAmount), true
        );
    }

    /**
     * @notice Trades perps of x and sqrt(x)
     * @param _vaultId The id of vault
     * @param _pairId The id of asset pair
     * @param _tradeParams The trade parameters
     * @return TradeResult The result of perp trade
     */
    function tradePerp(uint256 _vaultId, uint64 _pairId, TradePerpLogic.TradeParams memory _tradeParams)
        external
        override(IController)
        nonReentrant
        returns (DataType.TradeResult memory)
    {
        return TradePerpLogic.execTrade(globalData, _vaultId, _pairId, _tradeParams);
    }

    function setAutoTransfer(uint256 _isolatedVaultId, bool _autoTransferDisabled) external {
        VaultLib.checkVault(globalData.vaults[_isolatedVaultId], msg.sender);

        globalData.vaults[_isolatedVaultId].autoTransferDisabled = _autoTransferDisabled;
    }

    /**
     * @notice Executes liquidation call and gets reward.
     * Anyone can call this function.
     * @param _vaultId The id of vault
     * @param _closeRatio If you'll close all position, set 1e18.
     * @param _sqrtSlippageTolerance if caller is liquidator, the caller can set custom slippage tolerance.
     */
    function liquidationCall(uint256 _vaultId, uint256 _closeRatio, uint256 _sqrtSlippageTolerance)
        external
        nonReentrant
    {
        require(msg.sender == liquidator || _sqrtSlippageTolerance == 0);

        LiquidationLogic.execLiquidationCall(globalData, _vaultId, _closeRatio, _sqrtSlippageTolerance);
    }

    ///////////////////////
    // Private Functions //
    ///////////////////////

    // Getter functions

    /**
     * Gets square root of current underlying token price by quote token.
     */
    function getSqrtPrice(uint256 _tokenId) external view override(IController) returns (uint160) {
        return UniHelper.convertSqrtPrice(
            UniHelper.getSqrtPrice(globalData.pairs[_tokenId].sqrtAssetStatus.uniswapPool),
            globalData.pairs[_tokenId].isMarginZero
        );
    }

    function getSqrtIndexPrice(uint256 _tokenId) external view returns (uint160) {
        return UniHelper.convertSqrtPrice(
            UniHelper.getSqrtTWAP(globalData.pairs[_tokenId].sqrtAssetStatus.uniswapPool),
            globalData.pairs[_tokenId].isMarginZero
        );
    }

    function getPairGroup(uint256 _id) external view override(IController) returns (DataType.PairGroup memory) {
        return globalData.pairGroups[_id];
    }

    function getAsset(uint256 _id) external view override(IController) returns (DataType.PairStatus memory) {
        return globalData.pairs[_id];
    }

    function getLatestAssetStatus(uint256 _id) external returns (DataType.PairStatus memory) {
        return ReaderLogic.getLatestAssetStatus(globalData, _id);
    }

    function getVault(uint256 _id) external view override(IController) returns (DataType.Vault memory) {
        return globalData.vaults[_id];
    }

    /**
     * @notice Gets latest vault status.
     * @dev This function should not be called on chain.
     * @param _vaultId The id of the vault
     */
    function getVaultStatus(uint256 _vaultId) public returns (DataType.VaultStatusResult memory) {
        DataType.Vault storage vault = globalData.vaults[_vaultId];

        return ReaderLogic.getVaultStatus(globalData.pairs, globalData.rebalanceFeeGrowthCache, vault);
    }

    /**
     * @notice Gets latest main vault status that the caller has.
     * @dev This function should not be called on chain.
     */
    function getVaultStatusWithAddress(uint256 _pairGroupId)
        external
        returns (DataType.VaultStatusResult memory, DataType.VaultStatusResult[] memory)
    {
        DataType.OwnVaults memory ownVaults = globalData.ownVaultsMap[msg.sender][_pairGroupId];

        DataType.VaultStatusResult[] memory vaultStatusResults =
            new DataType.VaultStatusResult[](ownVaults.isolatedVaultIds.length);

        for (uint256 i; i < ownVaults.isolatedVaultIds.length; i++) {
            vaultStatusResults[i] = getVaultStatus(ownVaults.isolatedVaultIds[i]);
        }

        return (getVaultStatus(ownVaults.mainVaultId), vaultStatusResults);
    }
}

