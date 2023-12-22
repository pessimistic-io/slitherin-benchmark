// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

import {OrangeAlphaVault, IERC20, LiquidityAmounts, OracleLibrary, TickMath, FullMath} from "./OrangeAlphaVault.sol";
import {IOrangeAlphaParameters} from "./IOrangeAlphaPeriphery.sol";
import {IUniswapV3Pool} from "./UniswapV3Twap.sol";

struct Positions {
    uint256 debtAmount0; //debt amount of token0 on Lending
    uint256 collateralAmount1; //collateral amount of token1 on Lending
    uint256 token0Balance; //balance of token0
    uint256 token1Balance; //balance of token1
}

contract OrangeAlphaComputationMock {
    using TickMath for int24;
    using FullMath for uint256;

    uint256 constant MAGIC_SCALE_1E8 = 1e8; //for computing ltv
    uint16 constant MAGIC_SCALE_1E4 = 10000; //for slippage

    /* ========== PARAMETERS ========== */
    OrangeAlphaVault public vault;
    IOrangeAlphaParameters public params;
    IERC20 public token0;
    IERC20 public token1;

    /* ========== CONSTRUCTOR ========== */
    constructor(address _vault, address _params) {
        vault = OrangeAlphaVault(_vault);
        params = IOrangeAlphaParameters(_params);
        token0 = vault.token0();
        token1 = vault.token1();
    }

    /// @notice Compute the amount of collateral/debt to Aave and token0/token1 to Uniswap
    function computeRebalancePosition(
        int24 _lowerTick,
        int24 _upperTick,
        uint256 _ltv,
        uint256 _hedgeRatio
    ) external view returns (Positions memory) {
        IUniswapV3Pool _pool = vault.pool();
        (, int24 _currentTick, , , , , ) = _pool.slot0();
        uint _assets = vault.totalAssets();

        if (_assets == 0) return Positions(0, 0, 0, 0);

        // compute ETH/USDC amount ration to add liquidity
        (uint256 _amount0, uint256 _amount1) = LiquidityAmounts.getAmountsForLiquidity(
            _currentTick.getSqrtRatioAtTick(),
            _lowerTick.getSqrtRatioAtTick(),
            _upperTick.getSqrtRatioAtTick(),
            1e18 //any amount
        );
        uint256 _amount0ValueInToken1 = OracleLibrary.getQuoteAtTick(
            _currentTick,
            uint128(_amount0),
            address(token0),
            address(token1)
        );

        if (_hedgeRatio == 0) {
            uint _token1Balance = _assets.mulDiv(_amount1, (_amount0ValueInToken1 + _amount1));
            return Positions(0, 0, _token1Balance.mulDiv(_amount0, _amount1), _token1Balance);
        } else {
            return
                _computePositions(_assets, _amount0, _amount1, _amount0ValueInToken1, _currentTick, _ltv, _hedgeRatio);
        }
    }

    function _computePositions(
        uint _assets,
        uint _amount0,
        uint _amount1,
        uint _amount0ValueInToken1,
        int24 _currentTick,
        uint256 _ltv,
        uint256 _hedgeRatio
    ) internal view returns (Positions memory position_) {
        //compute collateral/asset ratio
        uint256 _x = MAGIC_SCALE_1E8.mulDiv(_amount1, _amount0ValueInToken1);
        uint256 _collateralRatioReciprocal = MAGIC_SCALE_1E8 -
            _ltv +
            MAGIC_SCALE_1E8.mulDiv(_ltv, _hedgeRatio) +
            MAGIC_SCALE_1E8.mulDiv(_ltv, _hedgeRatio).mulDiv(_x, MAGIC_SCALE_1E8);

        //Collateral
        position_.collateralAmount1 = _assets.mulDiv(MAGIC_SCALE_1E8, _collateralRatioReciprocal);

        uint256 _borrowUsdc = position_.collateralAmount1.mulDiv(_ltv, MAGIC_SCALE_1E8);
        //borrowing usdc amount to weth
        position_.debtAmount0 = OracleLibrary.getQuoteAtTick(
            _currentTick,
            uint128(_borrowUsdc),
            address(token1),
            address(token0)
        );

        // amount added on Uniswap
        position_.token0Balance = position_.debtAmount0.mulDiv(MAGIC_SCALE_1E8, _hedgeRatio);
        position_.token1Balance = position_.token0Balance.mulDiv(_amount1, _amount0);
    }

    ///@notice Get LTV by current and range prices
    ///@dev called by _computeRebalancePosition. maxLtv * (current price / upper price)
    function getLtvByRange(int24 _currentTick, int24 _upperTick) external view returns (uint256 ltv_) {
        uint256 _currentPrice = _quoteEthPriceByTick(_currentTick);
        uint256 _upperPrice = _quoteEthPriceByTick(_upperTick);
        ltv_ = params.maxLtv();
        if (_currentPrice < _upperPrice) {
            ltv_ = ltv_.mulDiv(_currentPrice, _upperPrice);
        }
    }

    ///@notice Quote eth price by USDC
    function _quoteEthPriceByTick(int24 _tick) internal view returns (uint256) {
        return OracleLibrary.getQuoteAtTick(_tick, 1 ether, address(token0), address(token1));
    }
}

