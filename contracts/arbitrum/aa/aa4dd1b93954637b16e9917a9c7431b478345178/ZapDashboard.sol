// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "./SafeMath.sol";

import "./library_Math.sol";

import "./IBEP20.sol";
import "./IZapDashboard.sol";
import "./IZap.sol";
import "./IWhiteholePair.sol";
import "./ILpVaultDashboard.sol";
import "./IDashboard.sol";
import "./IWhiteholeRouter.sol";

contract ZapDashboard is IZapDashboard {
    using SafeMath for uint256;

    /* ========== STATE VARIABLES ========== */

    IZap public zap;
    IWhiteholePair public GRV_USDC_LP;
    IWhiteholeRouter public whiteholeRouter;
    ILpVaultDashboard public lpVaultDashboard;
    address public GRV;

    /* ========== INITIALIZER ========== */

    constructor(
        address _zap,
        address _GRV_USDC_LP,
        address _whiteholeRouter,
        address _GRV,
        address _lpVaultDashboard
    ) public {
        zap = IZap(_zap);
        GRV_USDC_LP = IWhiteholePair(_GRV_USDC_LP);
        whiteholeRouter = IWhiteholeRouter(_whiteholeRouter);
        GRV = _GRV;
        lpVaultDashboard = ILpVaultDashboard(_lpVaultDashboard);
    }

    /* ========== VIEWS ========== */

    function estimatedReceiveLpData(address _token, uint256 _amount) external view override returns (uint256, uint256) {
        address token0 = GRV_USDC_LP.token0();
        uint256 _tokenAmount = _amount;

        uint256 _sellAmount = _amount.div(2);

        (uint256 _reserve0, uint256 _reserve1, ) = GRV_USDC_LP.getReserves();

        uint256 _otherAmount;
        if (_token == token0) {
            _otherAmount = whiteholeRouter.getAmountOut(_sellAmount, _reserve0, _reserve1);
        } else {
            _otherAmount = whiteholeRouter.getAmountOut(_sellAmount, _reserve1, _reserve0);
        }

        uint256 _liquidity;
        uint256 _lpTotalSupply = GRV_USDC_LP.totalSupply();

        if (_lpTotalSupply == 0) {
            _liquidity = Math.sqrt(_tokenAmount.sub(_sellAmount).mul(_otherAmount)).sub(GRV_USDC_LP.MINIMUM_LIQUIDITY());
        } else {
            uint256 amount0;
            uint256 amount1;

            if (token0 == GRV) {
                if (_token == GRV) { // token0 is GRV, sell token is GRV
                    amount0 = _tokenAmount.sub(_sellAmount);
                    amount1 = _otherAmount;
                } else { // token0 is GRV, sell token is USDC
                    amount0 = _otherAmount;
                    amount1 = _tokenAmount.sub(_sellAmount);
                }
            } else {
                if (_token == GRV) { // token0 is USDC, sell token is GRV
                    amount0 = _otherAmount;
                    amount1 = _tokenAmount.sub(_sellAmount);
                } else { // token0 is USDC, sell token is USDC
                    amount0 = _tokenAmount.sub(_sellAmount);
                    amount1 = _otherAmount;
                }
            }
            _liquidity = Math.min(amount0.mul(_lpTotalSupply) / _reserve0, amount1.mul(_lpTotalSupply) / _reserve1);
        }
        return (_liquidity, lpVaultDashboard.calculateLpValueInUSD(_liquidity));
    }

    function getLiquidityInfo(
        address token,
        uint256 tokenAmount
    ) external view override returns (uint256, uint256) {
        if (tokenAmount == 0) {
            return (0, 0);
        }
        (uint256 _reserve0, uint256 _reserve1, ) = GRV_USDC_LP.getReserves();

        uint256 _lpTotalSupply = GRV_USDC_LP.totalSupply();

        uint256 _quote;
        uint256 _liquidity;

        if (token == GRV_USDC_LP.token0()) {
            _quote = whiteholeRouter.quote(tokenAmount, _reserve0, _reserve1);
        } else {
            _quote = whiteholeRouter.quote(tokenAmount, _reserve1, _reserve0);
        }

        if (_lpTotalSupply == 0) {
            _liquidity = Math.sqrt(tokenAmount.mul(_quote)).sub(GRV_USDC_LP.MINIMUM_LIQUIDITY());
        } else {
            if (token == GRV_USDC_LP.token0()) {
                _liquidity = Math.min(tokenAmount.mul(_lpTotalSupply) / _reserve0, _quote.mul(_lpTotalSupply) / _reserve1);
            } else {
                _liquidity = Math.min(tokenAmount.mul(_lpTotalSupply) / _reserve1, _quote.mul(_lpTotalSupply) / _reserve0);
            }
        }
        return (_quote, _liquidity);
    }

    function getTokenAmount(
        uint256 tokenAmount
    ) external view override returns (uint256, uint256) {
        if (tokenAmount == 0) {
            return (0, 0);
        }
        uint256 balance0 = IBEP20(GRV_USDC_LP.token0()).balanceOf(address(GRV_USDC_LP));
        uint256 balance1 = IBEP20(GRV_USDC_LP.token1()).balanceOf(address(GRV_USDC_LP));

        uint256 liquidity = tokenAmount;
        uint256 totalSupply = GRV_USDC_LP.totalSupply();

        uint256 token0Amount = liquidity.mul(balance0).div(totalSupply);
        uint256 token1Amount = liquidity.mul(balance1).div(totalSupply);

        return (token0Amount, token1Amount);
    }
}

