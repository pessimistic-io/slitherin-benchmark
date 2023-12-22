pragma solidity 0.8.18;

import {FixedPoint} from "./FixedPoint.sol";
import {IUniswapV2Pair} from "./IUniswapV2Pair.sol";
import {UniswapV2OracleLibrary} from "./UniswapV2OracleLibrary.sol";

struct PairOracle {
    IUniswapV2Pair pair;
    address token;
    FixedPoint.uq112x112 priceAverage;
    uint256 lastBlockTimestamp;
    uint256 priceCumulativeLast;
    uint256 lastTWAP;
}

library PairOracleTWAP {
    using FixedPoint for *;

    uint256 constant PRECISION = 1e18; // 1 LVL

    function currentTWAP(PairOracle storage self) internal view returns (uint256) {
        if (self.lastBlockTimestamp == 0) {
            return 0;
        }

        (uint256 price0Cumulative, uint256 price1Cumulative,) =
            UniswapV2OracleLibrary.currentCumulativePrices(address(self.pair));

        // Overflow is desired, casting never truncates
        unchecked {
            uint256 currentBlockTimestamp = block.timestamp % 2 ** 32;
            uint256 timeElapsed = currentBlockTimestamp - self.lastBlockTimestamp; // Overflow is desired
            FixedPoint.uq112x112 memory priceAverage = FixedPoint.uq112x112(
                uint224(
                    (
                        (self.token == self.pair.token0() ? price0Cumulative : price1Cumulative)
                            - self.priceCumulativeLast
                    ) / timeElapsed
                )
            );
            return priceAverage.mul(PRECISION).decode144();
        }
    }

    function update(PairOracle storage self) internal {
        (uint256 price0Cumulative, uint256 price1Cumulative, uint256 blockTimestamp) =
            UniswapV2OracleLibrary.currentCumulativePrices(address(self.pair));

        uint256 newPriceCumulativeLast = self.token == self.pair.token0() ? price0Cumulative : price1Cumulative;

        // Overflow is desired, casting never truncates
        unchecked {
            uint256 timeElapsed = blockTimestamp - self.lastBlockTimestamp; // Overflow is desired
            // Cumulative price is in (uq112x112 price * seconds) units so we simply wrap it after division by time elapsed
            self.priceAverage =
                FixedPoint.uq112x112(uint224((newPriceCumulativeLast - self.priceCumulativeLast) / timeElapsed));
            self.priceCumulativeLast = newPriceCumulativeLast;
        }

        if (self.lastBlockTimestamp != 0) {
            self.lastTWAP = self.priceAverage.mul(PRECISION).decode144();
        }
        self.lastBlockTimestamp = blockTimestamp;
    }
}

