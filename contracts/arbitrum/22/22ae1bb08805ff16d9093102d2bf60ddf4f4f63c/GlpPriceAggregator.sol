// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IERC20} from "./IERC20.sol";
import {IAggregatorV3} from "./IAggregatorV3.sol";
import {IGlpManager} from "./IGlpManager.sol";

contract GlpPriceAggregator is IAggregatorV3 {
    IERC20 public constant GLP = IERC20(0x4277f8F2c384827B5273592FF7CeBd9f2C1ac258);
    IGlpManager public constant GLP_MANAGER = IGlpManager(0x321F653eED006AD1C29D174e17d96351BDe22649);

    uint256 initialTime;

    constructor() {
        initialTime = block.timestamp;
    }

    function decimals() external pure returns (uint8) {
        return 12;
    }

    function description() external pure returns (string memory) {
        return "";
    }

    function version() external pure returns (uint256) {
        return 1;
    }

    function getRoundData(uint80)
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (1, _getPrice(), initialTime, initialTime, 1);
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (1, _getPrice(), initialTime, initialTime, 1);
    }

    function _getPrice() internal view returns (int256) {
        return int256(GLP_MANAGER.getAum(true) / GLP.totalSupply());
    }
}

