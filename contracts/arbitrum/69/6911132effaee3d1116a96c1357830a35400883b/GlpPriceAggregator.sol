// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IERC20} from "./IERC20.sol";
import {IAggregatorV3} from "./IAggregatorV3.sol";
import {IGlpManager} from "./IGlpManager.sol";
import {Keepable, Governable} from "./Keepable.sol";

contract GlpPriceAggregator is IAggregatorV3, Keepable {
    IERC20 public constant GLP = IERC20(0x4277f8F2c384827B5273592FF7CeBd9f2C1ac258);
    IGlpManager public constant GLP_MANAGER = IGlpManager(0x3963FfC9dff443c2A94f21b129D429891E32ec18);

    uint256 initialTime;
    int256 price;

    constructor() Governable(msg.sender) {
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
        return (1, price, initialTime, initialTime, 1);
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (1, price, initialTime, initialTime, 1);
    }

    function setPrice(uint256 _price) external onlyKeeper {
        price = int256(_price);
    }
}

