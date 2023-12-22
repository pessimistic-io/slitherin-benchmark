// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.6.12;

// Libraries
import {OracleLibrary} from "./OracleLibrary.sol";

// Contracts
import {Ownable} from "./Ownable.sol";

interface IChainlinkV3Aggregator {
    function decimals() external view returns (uint8);

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
}

contract GmxPriceOracle is Ownable {
    address public constant weth = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address public constant gmx = 0xfc5A1A6EB076a2C7aD06eD22C90d7E710E35ad0a;
    address public constant gmxWethUniV3Pool =
        0x80A9ae39310abf666A87C743d6ebBD0E8C42158E;
    address public constant ethChainlinkAggregator =
        0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612;

    uint32 public twapPeriod = 1800; // in seconds

    event TwapPeriodUpdate(uint32 _twapPeriod);

    function updateTwapPeriod(uint32 _twapPeriod) external onlyOwner {
        twapPeriod = _twapPeriod;

        emit TwapPeriodUpdate(_twapPeriod);
    }

    function getPriceInUSD() external view returns (uint256) {
        uint256 priceInETH = getPriceInETH(twapPeriod);

        uint256 ethPriceInUSD = getETHPriceInUSD();

        return (priceInETH * ethPriceInUSD) / 1e18;
    }

    function getPriceInETH(uint32 _twapPeriod) public view returns (uint256) {
        (int24 arithmeticMeanTick, ) = OracleLibrary.consult(
            gmxWethUniV3Pool,
            _twapPeriod
        );

        return
            OracleLibrary.getQuoteAtTick(
                arithmeticMeanTick,
                1e18, // Amount is 1 in 18 decimals
                gmx, // Base asset is GMX
                weth // quote asset is ETH
            );
    }

    function getETHPriceInUSD() public view returns (uint256) {
        (, int256 price, , , ) = IChainlinkV3Aggregator(ethChainlinkAggregator)
            .latestRoundData();

        return uint256(price);
    }
}

