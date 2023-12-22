// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import {IERC20} from "./IERC20.sol";
import {FixedPoint} from "./FixedPoint.sol";
import {PairOracleTWAP, PairOracle} from "./PairOracleTWAP.sol";
import {IUniswapV2Pair} from "./IUniswapV2Pair.sol";

contract LVLTwapOracle {
    using PairOracleTWAP for PairOracle;

    uint256 private constant PRECISION = 1e6;

    address public updater;
    uint256 public lastTWAP;

    PairOracle public lvlUsdtPair;

    constructor(address _lvl, address _lvlUsdtPair, address _updater) {
        require(_lvl != address(0), "invalid address");
        require(_lvlUsdtPair != address(0), "invalid address");
        require(_updater != address(0), "invalid address");
        lvlUsdtPair = PairOracle({
            pair: IUniswapV2Pair(_lvlUsdtPair),
            token: _lvl,
            priceAverage: FixedPoint.uq112x112(0),
            lastBlockTimestamp: 0,
            priceCumulativeLast: 0,
            lastTWAP: 0
        });
        updater = _updater;
    }

    // =============== VIEW FUNCTIONS ===============

    function getCurrentTWAP() public view returns (uint256) {
        // round to 1e12
        return lvlUsdtPair.currentTWAP() / PRECISION;
    }

    // =============== USER FUNCTIONS ===============

    function update() external {
        require(msg.sender == updater, "!updater");
        lvlUsdtPair.update();
        lastTWAP = lvlUsdtPair.lastTWAP / PRECISION;
        emit PriceUpdated(block.timestamp, lastTWAP);
    }

    // ===============  EVENTS ===============
    event PriceUpdated(uint256 timestamp, uint256 price);
}

