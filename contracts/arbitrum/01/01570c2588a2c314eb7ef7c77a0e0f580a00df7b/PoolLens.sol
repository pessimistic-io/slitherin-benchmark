// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import {IPoolWithStorage} from "./IPoolWithStorage.sol";
import {ILiquidityCalculator} from "./ILiquidityCalculator.sol";
import {ILevelOracle} from "./ILevelOracle.sol";
import {ILPToken} from "./ILPToken.sol";
import {SignedIntMath} from "./SignedIntMath.sol";
import {PositionLogic as PositionUtils} from "./PositionLogic.sol";
import {SafeCast} from "./SafeCast.sol";
import {DataTypes} from "./DataTypes.sol";
import {MathUtils} from "./MathUtils.sol";
import {Constants} from "./Constants.sol";

contract PoolLens {
    using SignedIntMath for int256;
    using SafeCast for uint256;
    using SafeCast for int256;

    struct PositionView {
        address owner;
        bytes32 key;
        address indexToken;
        DataTypes.Side side;
        address collateralToken;
        bool hasProfit;
        uint256 size;
        uint256 collateralValue;
        uint256 entryPrice;
        uint256 pnl;
        uint256 reserveAmount;
        uint256 borrowIndex;
        uint256 revision;
    }

    struct PoolAsset {
        uint256 poolAmount;
        uint256 reservedAmount;
        uint256 feeReserve;
        uint256 guaranteedValue;
        uint256 totalShortSize;
        uint256 averageShortPrice;
        uint256 poolBalance;
        uint256 lastAccrualTimestamp;
        uint256 borrowIndex;
    }

    IPoolWithStorage public immutable pool;

    constructor(address _pool) {
        require(_pool != address(0), "invalidAddress");
        pool = IPoolWithStorage(_pool);
    }

    function getLpPrice(address _tranche) external view returns (uint256) {
        if (!pool.isTranche(_tranche)) {
            revert InvalidTranche();
        }

        uint256 lpSupply = ILPToken(_tranche).totalSupply();
        ILiquidityCalculator liquidityCalculator = pool.liquidityCalculator();
        return
            lpSupply == 0 ? Constants.LP_INITIAL_PRICE : liquidityCalculator.getTrancheValue(_tranche, true) / lpSupply;
    }

    function poolAssets(address _token) external view returns (PoolAsset memory poolAsset) {
        DataTypes.AssetInfo memory asset = pool.getPoolAsset(_token);

        uint256 avgShortPrice;
        address[] memory tranches = pool.getAllTranches();
        for (uint256 i = 0; i < tranches.length;) {
            address tranche = tranches[i];
            DataTypes.AssetInfo memory trancheAsset = pool.trancheAssets(tranche, _token);
            avgShortPrice += trancheAsset.totalShortSize * trancheAsset.averageShortPrice;
            unchecked {
                ++i;
            }
        }
        poolAsset.poolAmount = asset.poolAmount;
        poolAsset.reservedAmount = asset.reservedAmount;
        poolAsset.guaranteedValue = asset.guaranteedValue;
        poolAsset.totalShortSize = asset.totalShortSize;
        poolAsset.feeReserve = pool.feeReserves(_token);
        poolAsset.averageShortPrice = asset.totalShortSize == 0 ? 0 : avgShortPrice / asset.totalShortSize;
        poolAsset.poolBalance = pool.poolBalances(_token);
        poolAsset.lastAccrualTimestamp = pool.lastAccrualTimestamps(_token);
        poolAsset.borrowIndex = pool.borrowIndices(_token);
    }

    function getPosition(address _owner, address _indexToken, address _collateralToken, DataTypes.Side _side)
        public
        view
        returns (PositionView memory result)
    {
        ILevelOracle oracle = pool.oracle();
        bytes32 positionKey = _getPositionKey(_owner, _indexToken, _collateralToken, _side);
        DataTypes.Position memory position = pool.positions(positionKey);

        if (position.size == 0) {
            return result;
        }

        uint256 indexPrice =
            _side == DataTypes.Side.LONG ? oracle.getPrice(_indexToken, false) : oracle.getPrice(_indexToken, true);
        int256 pnl = PositionUtils.calcPnl(_side, position.size, position.entryPrice, indexPrice);

        result.owner = _owner;
        result.key = positionKey;
        result.side = _side;
        result.size = position.size;
        result.collateralValue = position.collateralValue;
        result.pnl = pnl.abs();
        result.hasProfit = pnl > 0;
        result.entryPrice = position.entryPrice;
        result.borrowIndex = position.borrowIndex;
        result.reserveAmount = position.reserveAmount;
        result.collateralToken = _collateralToken;
        result.indexToken = _indexToken;
        result.revision = pool.positionRevisions(positionKey);
    }

    function _getPositionKey(address _owner, address _indexToken, address _collateralToken, DataTypes.Side _side)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(_owner, _indexToken, _collateralToken, _side));
    }

    function getTrancheValue(address _tranche, bool _max) public view returns (uint256) {
        return pool.liquidityCalculator().getTrancheValue(_tranche, _max);
    }

    function getPoolValue(bool _max) public view returns (uint256) {
        return pool.liquidityCalculator().getPoolValue(_max);
    }

    function getTrancheValue(address _tranche) external view returns (uint256) {
        return MathUtils.average(getTrancheValue(_tranche, true), getTrancheValue(_tranche, true));
    }

    function getPoolValue() external view returns (uint256) {
        return MathUtils.average(getPoolValue(true), getPoolValue(false));
    }

    struct PoolInfo {
        uint256 minValue;
        uint256 maxValue;
        uint256[] tranchesMinValue;
        uint256[] tranchesMaxValue;
    }

    function getPoolInfo() external view returns (PoolInfo memory info) {
        info.minValue = getPoolValue(false);
        info.maxValue = getPoolValue(true);
        address[] memory allTranches = pool.getAllTranches();
        uint256 nTranches = allTranches.length;
        info.tranchesMinValue = new uint[](nTranches);
        info.tranchesMaxValue = new uint[](nTranches);
        for (uint256 i = 0; i < nTranches;) {
            info.tranchesMinValue[i] = getTrancheValue(allTranches[i], false);
            info.tranchesMaxValue[i] = getTrancheValue(allTranches[i], true);
            unchecked {
                ++i;
            }
        }
    }

    function getAssetAum(address _tranche, address _token, bool _max) external view returns (uint256) {
        bool isStable = pool.isStableCoin(_token);
        ILevelOracle oracle = pool.oracle();
        uint256 price = oracle.getPrice(_token, _max);
        DataTypes.AssetInfo memory asset = pool.trancheAssets(_tranche, _token);
        if (isStable) {
            return asset.poolAmount * price;
        } else {
            int256 shortPnl =
                PositionUtils.calcPnl(DataTypes.Side.SHORT, asset.totalShortSize, asset.averageShortPrice, price);
            int256 aum =
                ((asset.poolAmount - asset.reservedAmount) * price + asset.guaranteedValue).toInt256() - shortPnl;
            return aum.toUint256();
        }
    }

    function getAssetPoolAum(address _token, bool _max) external view returns (uint256) {
        bool isStable = pool.isStableCoin(_token);
        uint256 price = pool.oracle().getPrice(_token, _max);
        address[] memory allTranches = pool.getAllTranches();

        int256 sum = 0;

        for (uint256 i = 0; i < allTranches.length;) {
            address _tranche = allTranches[i];
            DataTypes.AssetInfo memory asset = pool.trancheAssets(_tranche, _token);
            if (isStable) {
                sum = sum + (asset.poolAmount * price).toInt256();
            } else {
                uint256 averageShortPrice = asset.averageShortPrice;
                int256 shortPnl =
                    PositionUtils.calcPnl(DataTypes.Side.SHORT, asset.totalShortSize, averageShortPrice, price);
                sum = ((asset.poolAmount - asset.reservedAmount) * price + asset.guaranteedValue).toInt256() + sum
                    - shortPnl;
            }
            unchecked {
                ++i;
            }
        }

        return sum.toUint256();
    }

    function getUserPositions(address _user) external view returns (PositionView[] memory) {
        (address[] memory tokens, bool[] memory isStableCoin) = pool.getAllAssets();
        uint256 count = tokens.length;
        PositionView[] memory tmp = new PositionView[](count + count * count);
        uint256 idx;
        for (uint256 i = 0; i < count; ++i) {
            if (isStableCoin[i]) {
                address collateralToken = tokens[i];
                for (uint256 j = 0; j < count; j++) {
                    if (isStableCoin[j]) {
                        continue;
                    }
                    address indexToken = tokens[j];
                    PositionView memory position = getPosition(_user, indexToken, collateralToken, DataTypes.Side.SHORT);
                    if (position.size > 0) {
                        tmp[idx] = position;
                        ++idx;
                    }
                }
            } else {
                address indexToken = tokens[i];
                PositionView memory position = getPosition(_user, indexToken, indexToken, DataTypes.Side.LONG);
                if (position.size > 0) {
                    tmp[idx] = position;
                    ++idx;
                }
            }
        }

        PositionView[] memory results = new PositionView[](idx);
        for (uint256 i = 0; i < results.length; ++i) {
            results[i] = tmp[i];
        }

        return results;
    }

    error InvalidTranche();
}

