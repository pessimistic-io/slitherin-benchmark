// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.19;

import {IERC20Metadata} from "./IERC20Metadata.sol";
import {IERC20} from "./IERC20.sol";
import "./DataType.sol";
import "./PairGroupLib.sol";
import "./SupplyToken.sol";

library AddPairLogic {
    event PairAdded(uint256 pairId, uint256 pairGroupId, address _uniswapPool);
    event PairGroupAdded(uint256 id, address stableAsset);
    event AssetRiskParamsUpdated(uint256 pairId, DataType.AssetRiskParams riskParams);
    event IRMParamsUpdated(
        uint256 pairId, InterestRateModel.IRMParams stableIrmParams, InterestRateModel.IRMParams underlyingIrmParams
    );

    /**
     * @notice Initialized global data counts
     * @param _global Global data
     */
    function initializeGlobalData(DataType.GlobalData storage _global) external {
        _global.pairGroupsCount = 1;
        _global.pairsCount = 1;
        _global.vaultCount = 1;
    }

    /**
     * @notice Adds an pair group
     * @param _global Global data
     * @param _stableAssetAddress The address of stable asset
     * @param _marginRounder Margin rounder
     * @return pairGroupId Pair group id
     */
    function addPairGroup(DataType.GlobalData storage _global, address _stableAssetAddress, uint8 _marginRounder)
        external
        returns (uint256 pairGroupId)
    {
        pairGroupId = _global.pairGroupsCount;

        _global.pairGroups[pairGroupId] = DataType.PairGroup(pairGroupId, _stableAssetAddress, _marginRounder);

        _global.pairGroupsCount++;

        emit PairGroupAdded(pairGroupId, _stableAssetAddress);
    }

    /**
     * @notice Adds token pair
     */
    function addPair(
        DataType.GlobalData storage _global,
        mapping(address => bool) storage allowedUniswapPools,
        DataType.AddPairParams memory _addPairParam
    ) external returns (uint256 pairId) {
        pairId = _global.pairsCount;

        require(pairId < Constants.MAX_PAIRS, "MAXP");

        // Checks the pair group exists
        PairGroupLib.validatePairGroupId(_global, _addPairParam.pairGroupId);

        DataType.PairGroup memory pairGroup = _global.pairGroups[_addPairParam.pairGroupId];

        IUniswapV3Pool uniswapPool = IUniswapV3Pool(_addPairParam.uniswapPool);

        address stableTokenAddress = pairGroup.stableTokenAddress;

        require(uniswapPool.token0() == stableTokenAddress || uniswapPool.token1() == stableTokenAddress, "C3");

        bool isMarginZero = uniswapPool.token0() == stableTokenAddress;

        _storePairStatus(
            pairGroup,
            _global.pairs,
            pairId,
            isMarginZero ? uniswapPool.token1() : uniswapPool.token0(),
            isMarginZero,
            _addPairParam
        );

        allowedUniswapPools[_addPairParam.uniswapPool] = true;

        _global.pairsCount++;

        emit PairAdded(pairId, _addPairParam.pairGroupId, _addPairParam.uniswapPool);
    }

    function updateAssetRiskParams(DataType.PairStatus storage _pairStatus, DataType.AssetRiskParams memory _riskParams)
        external
    {
        validateRiskParams(_riskParams);

        _pairStatus.riskParams.riskRatio = _riskParams.riskRatio;
        _pairStatus.riskParams.rangeSize = _riskParams.rangeSize;
        _pairStatus.riskParams.rebalanceThreshold = _riskParams.rebalanceThreshold;

        emit AssetRiskParamsUpdated(_pairStatus.id, _riskParams);
    }

    function updateIRMParams(
        DataType.PairStatus storage _pairStatus,
        InterestRateModel.IRMParams memory _stableIrmParams,
        InterestRateModel.IRMParams memory _underlyingIrmParams
    ) external {
        validateIRMParams(_stableIrmParams);
        validateIRMParams(_underlyingIrmParams);

        _pairStatus.stablePool.irmParams = _stableIrmParams;
        _pairStatus.underlyingPool.irmParams = _underlyingIrmParams;

        emit IRMParamsUpdated(_pairStatus.id, _stableIrmParams, _underlyingIrmParams);
    }

    function _storePairStatus(
        DataType.PairGroup memory _pairGroup,
        mapping(uint256 => DataType.PairStatus) storage _pairs,
        uint256 _pairId,
        address _tokenAddress,
        bool _isMarginZero,
        DataType.AddPairParams memory _addPairParam
    ) internal {
        validateRiskParams(_addPairParam.assetRiskParams);

        require(_pairs[_pairId].id == 0);

        _pairs[_pairId] = DataType.PairStatus(
            _pairId,
            _pairGroup.id,
            DataType.AssetPoolStatus(
                _pairGroup.stableTokenAddress,
                deploySupplyToken(_pairGroup.stableTokenAddress),
                ScaledAsset.createTokenStatus(),
                _addPairParam.stableIrmParams
            ),
            DataType.AssetPoolStatus(
                _tokenAddress,
                deploySupplyToken(_tokenAddress),
                ScaledAsset.createTokenStatus(),
                _addPairParam.underlyingIrmParams
            ),
            _addPairParam.assetRiskParams,
            Perp.createAssetStatus(
                _addPairParam.uniswapPool,
                -_addPairParam.assetRiskParams.rangeSize,
                _addPairParam.assetRiskParams.rangeSize
            ),
            _isMarginZero,
            _addPairParam.isIsolatedMode,
            block.timestamp
        );

        emit AssetRiskParamsUpdated(_pairId, _addPairParam.assetRiskParams);
        emit IRMParamsUpdated(_pairId, _addPairParam.stableIrmParams, _addPairParam.underlyingIrmParams);
    }

    function deploySupplyToken(address _tokenAddress) internal returns (address) {
        IERC20Metadata erc20 = IERC20Metadata(_tokenAddress);

        return address(
            new SupplyToken(
            address(this),
            string.concat("Predy-Supply-", erc20.name()),
            string.concat("p", erc20.symbol()),
            erc20.decimals()
            )
        );
    }

    function validateRiskParams(DataType.AssetRiskParams memory _assetRiskParams) internal pure {
        require(1e8 < _assetRiskParams.riskRatio && _assetRiskParams.riskRatio <= 10 * 1e8, "C0");

        require(_assetRiskParams.rangeSize > 0 && _assetRiskParams.rebalanceThreshold > 0, "C0");
    }

    function validateIRMParams(InterestRateModel.IRMParams memory _irmParams) internal pure {
        require(
            _irmParams.baseRate <= 1e18 && _irmParams.kinkRate <= 1e18 && _irmParams.slope1 <= 1e18
                && _irmParams.slope2 <= 10 * 1e18,
            "C4"
        );
    }
}

