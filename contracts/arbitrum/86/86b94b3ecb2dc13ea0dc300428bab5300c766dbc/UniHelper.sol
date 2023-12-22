// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.19;

import "./IUniswapV3Pool.sol";
import "./TickMath.sol";
import "./IUniswapV3PoolOracle.sol";
import "./DataType.sol";
import "./Constants.sol";

library UniHelper {
    uint256 internal constant ORACLE_PERIOD = 30 minutes;

    function getSqrtPrice(address _uniswapPool) internal view returns (uint160 sqrtPrice) {
        (sqrtPrice,,,,,,) = IUniswapV3Pool(_uniswapPool).slot0();
    }

    /**
     * Gets square root of time weighted average price.
     */
    function getSqrtTWAP(address _uniswapPool) internal view returns (uint160 sqrtTwapX96) {
        (sqrtTwapX96,) = callUniswapObserve(IUniswapV3Pool(_uniswapPool), ORACLE_PERIOD);
    }

    /**
     * sqrt price in stable token
     */
    function convertSqrtPrice(uint160 _sqrtPriceX96, bool _isMarginZero) internal pure returns (uint160) {
        if (_isMarginZero) {
            return uint160((Constants.Q96 << Constants.RESOLUTION) / _sqrtPriceX96);
        } else {
            return _sqrtPriceX96;
        }
    }

    function callUniswapObserve(IUniswapV3Pool uniswapPool, uint256 ago) internal view returns (uint160, uint256) {
        uint32[] memory secondsAgos = new uint32[](2);

        secondsAgos[0] = uint32(ago);
        secondsAgos[1] = 0;

        (bool success, bytes memory data) =
            address(uniswapPool).staticcall(abi.encodeWithSelector(IUniswapV3PoolOracle.observe.selector, secondsAgos));

        if (!success) {
            if (keccak256(data) != keccak256(abi.encodeWithSignature("Error(string)", "OLD"))) {
                revertBytes(data);
            }

            (,, uint16 index, uint16 cardinality,,,) = uniswapPool.slot0();

            (uint32 oldestAvailableAge,,, bool initialized) = uniswapPool.observations((index + 1) % cardinality);

            if (!initialized) {
                (oldestAvailableAge,,,) = uniswapPool.observations(0);
            }

            ago = block.timestamp - oldestAvailableAge;
            secondsAgos[0] = uint32(ago);

            (success, data) = address(uniswapPool).staticcall(
                abi.encodeWithSelector(IUniswapV3PoolOracle.observe.selector, secondsAgos)
            );
            if (!success) {
                revertBytes(data);
            }
        }

        int56[] memory tickCumulatives = abi.decode(data, (int56[]));

        int24 tick = int24((tickCumulatives[1] - tickCumulatives[0]) / int56(int256(ago)));

        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(tick);

        return (sqrtPriceX96, ago);
    }

    function revertBytes(bytes memory errMsg) internal pure {
        if (errMsg.length > 0) {
            assembly {
                revert(add(32, errMsg), mload(errMsg))
            }
        }

        revert("e/empty-error");
    }

    function checkPriceByTWAP(address _uniswapPool) internal view {
        // reverts if price is out of slippage threshold
        uint160 sqrtTwap = getSqrtTWAP(_uniswapPool);
        uint256 sqrtPrice = getSqrtPrice(_uniswapPool);

        require(
            sqrtTwap * 1e6 / (1e6 + Constants.SLIPPAGE_SQRT_TOLERANCE) <= sqrtPrice
                && sqrtPrice <= sqrtTwap * (1e6 + Constants.SLIPPAGE_SQRT_TOLERANCE) / 1e6,
            "Slipped"
        );
    }
}

