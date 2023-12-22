// SPDX-License-Indetifier: MIT
pragma solidity ^0.8.10;

import {IUniswapV3Pool} from "./IUniswapV3Pool.sol";
import {OracleLibrary} from "./OracleLibrary.sol";
import {IMetadata} from "./IMetadata.sol";

library UniV3OracleLibrary {
    /// @notice The identifying key of the pool
    struct PoolKey {
        address token0;
        address token1;
        uint24 fee;
    }

    /**
     * @notice Get TWAP of token0 quoted in token1.
     * @param _secondsAgo Length of TWAP.
     */
    function getPrice(IUniswapV3Pool _pool, int24 _secondsAgo) public view returns (uint256) {
        // Avoid revert with arg 0 and get spot price.
        _secondsAgo = _secondsAgo == 0 ? int24(1) : _secondsAgo;

        uint32[] memory secondsAgo = new uint32[](2);

        secondsAgo[0] = uint32(uint24(_secondsAgo));
        secondsAgo[1] = 0;

        // Get cumulative ticks
        (int56[] memory tickCumulative,) = _pool.observe(secondsAgo);

        // Now get the cumulative tick just for the specified timeframe (_secondsAgo).
        int56 deltaCumulativeTicks = tickCumulative[1] - tickCumulative[0];

        // Get the arithmetic mean of the delta between the two cumulative ticks.
        int24 arithmeticMeanTick = int24(deltaCumulativeTicks / _secondsAgo);

        // Rounding to negative infinity.
        if (deltaCumulativeTicks < 0 && (deltaCumulativeTicks % _secondsAgo != 0)) {
            arithmeticMeanTick = arithmeticMeanTick - 1;
        }

        // One unit of token0, so we if for example token has 9 decimals, one unit will be 10 ** 9 = 1000000000.
        uint256 oneUnit = 10 ** IMetadata(_pool.token0()).decimals();

        return OracleLibrary.getQuoteAtTick(arithmeticMeanTick, uint128(oneUnit), _pool.token0(), _pool.token1());
    }

    function getSpot(IUniswapV3Pool _pool) public view returns (uint256) {
        return getPrice(_pool, 0);
    }

    function getPool(address factory, address tokenA, address tokenB, uint24 fee, bytes32 initCodeHash)
        public
        pure
        returns (IUniswapV3Pool)
    {
        return IUniswapV3Pool(computeAddress(factory, getPoolKey(tokenA, tokenB, fee), initCodeHash));
    }

    /// @notice Returns PoolKey: the ordered tokens with the matched fee levels
    /// @param tokenA The first token of a pool, unsorted
    /// @param tokenB The second token of a pool, unsorted
    /// @param fee The fee level of the pool
    /// @return Poolkey The pool details with ordered token0 and token1 assignments
    function getPoolKey(address tokenA, address tokenB, uint24 fee) private pure returns (PoolKey memory) {
        if (tokenA > tokenB) (tokenA, tokenB) = (tokenB, tokenA);
        return PoolKey({token0: tokenA, token1: tokenB, fee: fee});
    }

    /// @notice Deterministically computes the pool address given the factory and PoolKey
    /// @param factory The Uniswap V3 factory contract address
    /// @param key The PoolKey
    /// @return pool The contract address of the V3 pool
    function computeAddress(address factory, PoolKey memory key, bytes32 initCodeHash)
        private
        pure
        returns (address pool)
    {
        require(key.token0 < key.token1);
        pool = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            hex"ff", factory, keccak256(abi.encode(key.token0, key.token1, key.fee)), initCodeHash
                        )
                    )
                )
            )
        );
    }
}

