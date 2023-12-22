// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.7.6;
pragma abicoder v2;

import "./IUniswapV3Pool.sol";
import "./TickMath.sol";
import "./FullMath.sol";
import "./LiquidityAmounts.sol";
import "./ERC20.sol";
import "./SafeERC20.sol";
import "./SafeMath.sol";
import "./SignedSafeMath.sol";
import "./IVaultSwap.sol";
import "./IVaultEnterprise.sol";

import "./console.sol";

library VaultEnterpriseHelper {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using SignedSafeMath for int256;

    /// @notice Get the info of the given position
    /// @return _liquidity The amount of liquidity of the position
    /// @return _tokens0InPosition Amount of token0 owed
    /// @return _tokens1InPosition Amount of token1 owed
    function getPosition(
        IUniswapV3Pool _pool,
        int24 _tickLower,
        int24 _tickUpper
    )
        public
        view
        returns (
            uint128 _liquidity,
            uint128 _tokens0InPosition,
            uint128 _tokens1InPosition
        )
    {
        bytes32 _positionId = keccak256(
            abi.encodePacked(address(this), _tickLower, _tickUpper)
        );
        (_liquidity, , , _tokens0InPosition, _tokens1InPosition) = _pool
            .positions(_positionId);
    }

    /// @notice Get the amounts of the given numbers of liquidity tokens
    /// @param _liquidity The amount of liquidity tokens
    /// @return Amount of token0 and token1
    function getAmountsForLiquidity(
        IUniswapV3Pool _pool,
        int24 _tickLower,
        int24 _tickUpper,
        uint128 _liquidity
    ) public view returns (uint256, uint256) {
        (uint160 _sqrtRatioX96, , , , , , ) = _pool.slot0();
        return
            LiquidityAmounts.getAmountsForLiquidity(
                _sqrtRatioX96,
                TickMath.getSqrtRatioAtTick(_tickLower),
                TickMath.getSqrtRatioAtTick(_tickUpper),
                _liquidity
            );
    }

    /// @notice Get the liquidity for a given amount of token0 and token1
    /// @param _amount0 The amount token0
    /// @param _amount1 The amount token1
    /// @return _liquidity
    function getLiquidityForAmounts(
        IUniswapV3Pool _pool,
        int24 _tickLower,
        int24 _tickUpper,
        uint256 _amount0,
        uint256 _amount1
    ) external view returns (uint128 _liquidity) {
        (uint160 _sqrtRatioX96, , , , , , ) = _pool.slot0();
        return
            _liquidity = LiquidityAmounts.getLiquidityForAmounts(
                _sqrtRatioX96,
                TickMath.getSqrtRatioAtTick(_tickLower),
                TickMath.getSqrtRatioAtTick(_tickUpper),
                _amount0,
                _amount1
            );
    }

    /// @notice gets the liquidity and amounts of token 0 and 1 for the position
    /// @return _liquidity Amount of total liquidity in the base position
    /// @return _amount0 Estimated amount of token0 that could be collected by
    /// burning the base position
    /// @return _amount1 Estimated amount of token1 that could be collected by
    /// burning the base position
    function getPositionAmounts(
        IUniswapV3Pool _pool,
        int24 _tickLower,
        int24 _tickUpper
    )
        public
        view
        returns (uint128 _liquidity, uint256 _amount0, uint256 _amount1)
    {
        (
            uint128 _liquidityInPosition,
            uint128 _tokens0InPosition,
            uint128 _tokens1InPosition
        ) = getPosition(_pool, _tickLower, _tickUpper);
        (_amount0, _amount1) = getAmountsForLiquidity(
            _pool,
            _tickLower,
            _tickUpper,
            _liquidityInPosition
        );
        _amount0 = _amount0.add(uint256(_tokens0InPosition));
        _amount1 = _amount1.add(uint256(_tokens1InPosition));
        _liquidity = _liquidityInPosition;
    }

    /// @notice get the TotalAmounts of token0 and token1 in the Vault
    /// @return _total0 Quantity of token0 in position and unused in the Vault
    /// @return _total1 Quantity of token1 in position and unused in the Vault
    function getPositionTotalAmounts(
        IUniswapV3Pool _pool,
        int24 _tickLower,
        int24 _tickUpper,
        uint256 _balanceToken0,
        uint256 _balanceToken1
    ) public view returns (uint256 _total0, uint256 _total1) {
        (, uint256 _amount0, uint256 _amount1) = getPositionAmounts(
            _pool,
            _tickLower,
            _tickUpper
        );
        _total0 = _balanceToken0.add(_amount0);
        _total1 = _balanceToken1.add(_amount1);
    }

    /**
     * @notice Gets latest Uniswap price in the pool, token1 represented in price of token0
     * @notice pool Address of the Uniswap V3 pool
     */
    function getPoolPrice(
        IUniswapV3Pool _pool
    ) public view returns (uint256 _price) {
        (uint160 _sqrtRatioX96, , , , , , ) = _pool.slot0();
        uint256 _priceX192 = uint256(_sqrtRatioX96).mul(_sqrtRatioX96);
        _price = FullMath.mulDiv(_priceX192, 1e18, 1 << 192);

        return _price;
    }

    function safeUint128(
        uint256 _amountToConvert
    ) external pure returns (uint128) {
        assert(_amountToConvert <= type(uint128).max);
        return uint128(_amountToConvert);
    }
}

