//SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import {FixedPoint} from "./FixedPoint.sol";
import {UniswapV2OracleLibrary} from "./UniswapV2OracleLibrary.sol";
import {IUniswapV2Pair} from "./IUniswapV2Pair.sol";

contract TwapOracle {
    using FixedPoint for *;

    struct Oracle {
        address token0;
        address token1;
        uint256 price0CumulativeLast;
        uint256 price1CumulativeLast;
        uint32 blockTimestampLast;
        FixedPoint.uq112x112 price0Average;
        FixedPoint.uq112x112 price1Average;
    }

    mapping(address => Oracle) public oracleOfPair;

    function createAndUpdateOracle(IUniswapV2Pair _pair) external {
        Oracle memory oracle = oracleOfPair[address(_pair)];
        if (oracle.blockTimestampLast == 0) {
            createOracle(_pair);
            updateOracle(_pair);
        } else {
            updateOracle(_pair);
        }
    }

    // note this will always return 0 before update has been called successfully for the first time.
    function consult(
        address _pair,
        address _token,
        uint256 _amountIn
    ) external view returns (uint144 amountOut) {
        Oracle memory oracle = oracleOfPair[_pair];
        require(oracle.blockTimestampLast != 0, "TwapOracle: Not found");

        if (_token == oracle.token0) {
            amountOut = oracle.price0Average.mul(_amountIn).decode144();
        } else {
            require(_token == oracle.token1, "TwapOracle: Invalid token");
            amountOut = oracle.price1Average.mul(_amountIn).decode144();
        }
    }

    function createOracle(IUniswapV2Pair _pair) public {
        require(
            oracleOfPair[address(_pair)].blockTimestampLast == 0,
            "TwapOracle: Already created"
        );

        address token0 = _pair.token0();
        address token1 = _pair.token1();

        uint112 reserve0;
        uint112 reserve1;
        (reserve0, reserve1, ) = _pair.getReserves();

        require(reserve0 != 0 && reserve1 != 0, "TwapOracle: No reserves");

        (
            uint256 _price0Cumulative,
            uint256 _price1Cumulative,
            uint32 _blockTimestamp
        ) = UniswapV2OracleLibrary.currentCumulativePrices(_pair);

        oracleOfPair[address(_pair)] = Oracle(
            token0,
            token1,
            _price0Cumulative,
            _price1Cumulative,
            _blockTimestamp,
            FixedPoint.uq112x112(0),
            FixedPoint.uq112x112(0)
        );
    }

    function updateOracle(IUniswapV2Pair _pair) public {
        Oracle memory oracle = oracleOfPair[address(_pair)];
        Oracle storage s_oracle = oracleOfPair[address(_pair)];

        (
            uint256 price0Cumulative,
            uint256 price1Cumulative,
            uint32 blockTimestamp
        ) = UniswapV2OracleLibrary.currentCumulativePrices(_pair);
        uint32 timeElapsed = blockTimestamp - oracle.blockTimestampLast; // overflow is desired

        if (timeElapsed == 0) {
            // prevent divided by zero
            return;
        }

        // overflow is desired, casting never truncates
        // cumulative price is in (uq112x112 price * seconds) units so we simply wrap it after division by time elapsed
        s_oracle.price0Average = FixedPoint.uq112x112(
            uint224(
                (price0Cumulative - oracle.price0CumulativeLast) / timeElapsed
            )
        );
        s_oracle.price1Average = FixedPoint.uq112x112(
            uint224(
                (price1Cumulative - oracle.price1CumulativeLast) / timeElapsed
            )
        );

        s_oracle.price0CumulativeLast = price0Cumulative;
        s_oracle.price1CumulativeLast = price1Cumulative;
        s_oracle.blockTimestampLast = blockTimestamp;
    }
}

