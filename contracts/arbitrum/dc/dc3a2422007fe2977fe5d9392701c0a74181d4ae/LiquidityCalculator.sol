pragma solidity 0.8.18;

import {Ownable} from "./Ownable.sol";
import {ILevelOracle} from "./ILevelOracle.sol";
import {ILiquidityCalculator} from "./ILiquidityCalculator.sol";
import {IPoolWithStorage} from "./IPoolWithStorage.sol";
import {DataTypes} from "./DataTypes.sol";
import {PositionLogic} from "./PositionLogic.sol";
import {ILPToken} from "./ILPToken.sol";
import {MathUtils} from "./MathUtils.sol";
import {Constants} from "./Constants.sol";
import {SafeCast} from "./SafeCast.sol";

contract LiquidityCalculator is Ownable, ILiquidityCalculator {
    using SafeCast for uint256;
    using SafeCast for int256;

    uint256 constant MIN_SWAP_FEE = 15000000;

    IPoolWithStorage public immutable pool;

    /// @notice swap fee used when add/remove liquidity, swap token
    uint256 public baseSwapFee;
    /// @notice tax used to adjust swapFee due to the effect of the action on token's weight
    /// It reduce swap fee when user add some amount of a under weight token to the pool
    uint256 public taxBasisPoint;
    /// @notice swap fee used when add/remove liquidity, swap token
    uint256 public stableCoinBaseSwapFee;
    /// @notice tax used to adjust swapFee due to the effect of the action on token's weight
    /// It reduce swap fee when user add some amount of a under weight token to the pool
    uint256 public stableCoinTaxBasisPoint;

    uint256 public addRemoveLiquidityFee;

    constructor(
        address _pool,
        uint256 _baseSwapFee,
        uint256 _taxBasisPoint,
        uint256 _stableCoinBaseSwapFee,
        uint256 _stableCoinTaxBasisPoint,
        uint256 _addRemoveLiquidityFee
    ) {
        if (_pool == address(0)) revert InvalidAddress();
        pool = IPoolWithStorage(_pool);
        _setFees(_baseSwapFee, _taxBasisPoint, _stableCoinBaseSwapFee, _stableCoinTaxBasisPoint, _addRemoveLiquidityFee);
    }

    function getTrancheValue(address _tranche, bool _max) external view returns (uint256) {
        return _getTrancheValue(_tranche, _max);
    }

    function getPoolValue(bool _max) external view returns (uint256 sum) {
        address[] memory allTranches = pool.getAllTranches();
        (address[] memory allAssets, bool[] memory isStableCoin) = pool.getAllAssets();
        ILevelOracle oracle = pool.oracle();
        uint256[] memory prices = oracle.getMultiplePrices(allAssets, _max);

        for (uint256 i = 0; i < allTranches.length;) {
            sum += _getTrancheValue(allTranches[i], allAssets, isStableCoin, prices);
            unchecked {
                ++i;
            }
        }
    }

    function calcAddLiquidity(address _tranche, address _token, uint256 _amountIn)
        external
        view
        returns (uint256 lpAmount, uint256 feeAmount)
    {
        uint256 tokenPrice = _getPrice(_token, false);
        uint256 valueChange = _amountIn * tokenPrice;

        uint256 _fee = calcAddRemoveLiquidityFee(_token, tokenPrice, valueChange, true);
        uint256 userAmount = MathUtils.frac(_amountIn, Constants.PRECISION - _fee, Constants.PRECISION);
        feeAmount = _amountIn - userAmount;

        uint256 trancheValue = _getTrancheValue(_tranche, true);
        uint256 lpSupply = ILPToken(_tranche).totalSupply();
        if (lpSupply == 0 || trancheValue == 0) {
            lpAmount = MathUtils.frac(userAmount, tokenPrice, Constants.LP_INITIAL_PRICE);
        } else {
            lpAmount = userAmount * tokenPrice * lpSupply / trancheValue;
        }
    }

    function calcRemoveLiquidity(address _tranche, address _tokenOut, uint256 _lpAmount)
        external
        view
        returns (uint256 outAmountAfterFee, uint256 feeAmount)
    {
        uint256 tokenPrice = _getPrice(_tokenOut, true);
        uint256 trancheValue = _getTrancheValue(_tranche, false);
        uint256 valueChange = (_lpAmount * trancheValue) / ILPToken(_tranche).totalSupply();

        uint256 _fee = calcAddRemoveLiquidityFee(_tokenOut, tokenPrice, valueChange, false);
        uint256 outAmount = valueChange / tokenPrice;
        outAmountAfterFee = MathUtils.frac(outAmount, Constants.PRECISION - _fee, Constants.PRECISION);
        feeAmount = outAmount - outAmountAfterFee;
    }

    function calcSwapOutput(address _tokenIn, address _tokenOut, uint256 _amountIn)
        external
        view
        returns (uint256 amountOutAfterFee, uint256 feeAmount, uint256 priceIn, uint256 priceOut)
    {
        priceIn = _getPrice(_tokenIn, false);
        priceOut = _getPrice(_tokenOut, true);
        uint256 valueChange = _amountIn * priceIn;
        bool isStableSwap = pool.isStableCoin(_tokenIn) && pool.isStableCoin(_tokenOut);
        uint256 feeIn = calcSwapFee(isStableSwap, _tokenIn, priceIn, valueChange, true);
        uint256 feeOut = calcSwapFee(isStableSwap, _tokenOut, priceOut, valueChange, false);
        uint256 _fee = feeIn > feeOut ? feeIn : feeOut;

        amountOutAfterFee = valueChange * (Constants.PRECISION - _fee) / priceOut / Constants.PRECISION;
        feeAmount = (valueChange * _fee) / priceIn / Constants.PRECISION;
    }

    /// @notice calculate adjusted fee rate
    /// fee is increased or decreased based on action's effect to pool amount
    /// each token has their target weight set by gov
    /// if action make the weight of token far from its target, fee will be increase, vice versa
    function calcSwapFee(bool _isStableSwap, address _token, uint256 _tokenPrice, uint256 _valueChange, bool _isSwapIn)
        public
        view
        returns (uint256)
    {
        (uint256 _baseSwapFee, uint256 _taxBasisPoint) =
            _isStableSwap ? (stableCoinBaseSwapFee, stableCoinTaxBasisPoint) : (baseSwapFee, taxBasisPoint);
        uint256 rate = _calcFeeRate(_token, _tokenPrice, _valueChange, _baseSwapFee, _taxBasisPoint, _isSwapIn);
        return _isStableSwap ? rate : max(rate, MIN_SWAP_FEE);
    }

    function calcAddRemoveLiquidityFee(address _token, uint256 _tokenPrice, uint256 _valueChange, bool _isAdd)
        public
        view
        returns (uint256)
    {
        return _calcFeeRate(_token, _tokenPrice, _valueChange, addRemoveLiquidityFee, taxBasisPoint, _isAdd);
    }

    // =========== ADMIN FUNCTION ============
    function setFees(
        uint256 _baseSwapFee,
        uint256 _taxBasisPoint,
        uint256 _stableCoinBaseSwapFee,
        uint256 _stableCoinTaxBasisPoint,
        uint256 _addRemoveLiquidityFee
    ) external onlyOwner {
        _setFees(_baseSwapFee, _taxBasisPoint, _stableCoinBaseSwapFee, _stableCoinTaxBasisPoint, _addRemoveLiquidityFee);
    }

    // ======== INTERNAL FUCTIONS =========

    function _setFees(
        uint256 _baseSwapFee,
        uint256 _taxBasisPoint,
        uint256 _stableCoinBaseSwapFee,
        uint256 _stableCoinTaxBasisPoint,
        uint256 _addRemoveLiquidityFee
    ) internal {
        _validateMaxValue(_baseSwapFee, Constants.MAX_BASE_SWAP_FEE);
        _validateMaxValue(_stableCoinBaseSwapFee, Constants.MAX_BASE_SWAP_FEE);
        _validateMaxValue(_addRemoveLiquidityFee, Constants.MAX_BASE_SWAP_FEE);
        _validateMaxValue(_taxBasisPoint, Constants.MAX_TAX_BASIS_POINT);
        _validateMaxValue(_stableCoinTaxBasisPoint, Constants.MAX_TAX_BASIS_POINT);

        baseSwapFee = _baseSwapFee;
        taxBasisPoint = _taxBasisPoint;
        stableCoinBaseSwapFee = _stableCoinBaseSwapFee;
        stableCoinTaxBasisPoint = _stableCoinTaxBasisPoint;
        addRemoveLiquidityFee = _addRemoveLiquidityFee;

        emit SwapFeeSet(_baseSwapFee, _taxBasisPoint, _stableCoinBaseSwapFee, _stableCoinTaxBasisPoint);
        emit AddRemoveLiquidityFeeSet(_addRemoveLiquidityFee);
    }

    function _validateMaxValue(uint256 _input, uint256 _max) internal pure {
        if (_input > _max) {
            revert ValueTooHigh(_max);
        }
    }

    function _calcFeeRate(
        address _token,
        uint256 _tokenPrice,
        uint256 _valueChange,
        uint256 _baseFee,
        uint256 _taxBasisPoint,
        bool _isIncrease
    ) internal view returns (uint256) {
        uint256 totalWeight = pool.totalWeight();
        uint256 _targetValue =
            totalWeight == 0 ? 0 : (pool.targetWeights(_token) * pool.virtualPoolValue()) / totalWeight;
        if (_targetValue == 0) {
            return _baseFee;
        }
        uint256 _currentValue = _tokenPrice * pool.getPoolAsset(_token).poolAmount;
        uint256 _nextValue = _isIncrease ? _currentValue + _valueChange : _currentValue - _valueChange;
        uint256 initDiff = MathUtils.diff(_currentValue, _targetValue);
        uint256 nextDiff = MathUtils.diff(_nextValue, _targetValue);
        if (nextDiff < initDiff) {
            uint256 feeAdjust = (_taxBasisPoint * initDiff) / _targetValue;
            uint256 rate = MathUtils.zeroCapSub(_baseFee, feeAdjust);
        } else {
            uint256 avgDiff = (initDiff + nextDiff) / 2;
            uint256 feeAdjust = avgDiff > _targetValue ? _taxBasisPoint : (_taxBasisPoint * avgDiff) / _targetValue;
            return _baseFee + feeAdjust;
        }
    }

    function _getTrancheValue(address _tranche, bool _max) internal view returns (uint256 sum) {
        ILevelOracle oracle = pool.oracle();
        (address[] memory allAssets, bool[] memory isStableCoin) = pool.getAllAssets();
        uint256[] memory prices = oracle.getMultiplePrices(allAssets, _max);

        return _getTrancheValue(_tranche, allAssets, isStableCoin, prices);
    }

    function _getTrancheValue(
        address _tranche,
        address[] memory allAssets,
        bool[] memory isStableCoin,
        uint256[] memory prices
    ) internal view returns (uint256 sum) {
        int256 aum;

        for (uint256 i = 0; i < allAssets.length;) {
            address token = allAssets[i];
            DataTypes.AssetInfo memory asset = pool.trancheAssets(_tranche, token);
            uint256 price = prices[i];
            if (isStableCoin[i]) {
                aum = aum + (price * asset.poolAmount).toInt256();
            } else {
                uint256 averageShortPrice = asset.averageShortPrice;
                int256 shortPnl =
                    PositionLogic.calcPnl(DataTypes.Side.SHORT, asset.totalShortSize, averageShortPrice, price);
                aum = aum + ((asset.poolAmount - asset.reservedAmount) * price + asset.guaranteedValue).toInt256()
                    - shortPnl;
            }
            unchecked {
                ++i;
            }
        }

        // aum MUST not be negative. If it is, please debug
        return aum.toUint256();
    }

    function _getPrice(address _token, bool _max) internal view returns (uint256) {
        ILevelOracle oracle = pool.oracle();
        return oracle.getPrice(_token, _max);
    }

    function _calcDaoFee(uint256 _feeAmount) internal view returns (uint256 _daoFee, uint256 lpFee) {
        _daoFee = MathUtils.frac(_feeAmount, pool.daoFee(), Constants.PRECISION);
        lpFee = _feeAmount - _daoFee;
    }

    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }
}

