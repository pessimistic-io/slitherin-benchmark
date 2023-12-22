// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.10;

import "./OverlayV1Feed.sol";
import "./AggregatorV3Interface.sol";

contract OverlayV1NFTPerpFeed is OverlayV1Feed {
    AggregatorV3Interface public immutable aggregator;
    string public description;
    uint8 public decimals;

    constructor(
        address _aggregator,
        uint256 _microWindow,
        uint256 _macroWindow,
        uint8 _decimal
    ) OverlayV1Feed(_microWindow, _macroWindow) {
        require(_aggregator != address(0), "Invalid feed");

        aggregator = AggregatorV3Interface(_aggregator);
        decimals = _decimal;
        description = aggregator.description();
    }

    function _fetch() internal view virtual override returns (Oracle.Data memory) {
        (uint80 roundId, , , , ) = aggregator.latestRoundData();

        (
            uint256 priceOverMicroWindow,
            uint256 priceOverMacroWindow,
            uint256 priceOneMacroWindowAgo
        ) = _getAveragePrice(roundId);

        return
            Oracle.Data({
                timestamp: block.timestamp,
                microWindow: microWindow,
                macroWindow: macroWindow,
                priceOverMicroWindow: priceOverMicroWindow,
                priceOverMacroWindow: priceOverMacroWindow,
                priceOneMacroWindowAgo: priceOneMacroWindowAgo,
                reserveOverMicroWindow: 0,
                hasReserve: false
            });
    }

    function _getAveragePrice(uint80 roundId)
        internal
        view
        returns (
            uint256 priceOverMicroWindow,
            uint256 priceOverMacroWindow,
            uint256 priceOneMacroWindowAgo
        )
    {
        // nextTimestamp will be next time stamp recorded from current round id
        uint256 nextTimestamp = block.timestamp;
        // these values will keep decreasing till zero,
        // until all data is used up in respective window
        uint256 _microWindow = microWindow;
        uint256 _macroWindow = macroWindow;

        // timestamp till which value need to be considered for macrowindow ago
        uint256 macroAgoTargetTimestamp = nextTimestamp - 2 * macroWindow;

        uint256 sumOfPriceMicroWindow;
        uint256 sumOfPriceMacroWindow;
        uint256 sumOfPriceMacroWindowAgo;

        while (true) {
            (, int256 answer, , uint256 updatedAt, ) = aggregator.getRoundData(roundId);

            if (_microWindow > 0) {
                uint256 dt = nextTimestamp - updatedAt < _microWindow
                    ? nextTimestamp - updatedAt
                    : _microWindow;
                sumOfPriceMicroWindow += dt * uint256(answer);
                _microWindow -= dt;
            }

            if (_macroWindow > 0) {
                uint256 dt = nextTimestamp - updatedAt < _macroWindow
                    ? nextTimestamp - updatedAt
                    : _macroWindow;
                sumOfPriceMacroWindow += dt * uint256(answer);
                _macroWindow -= dt;
            }

            if (updatedAt <= block.timestamp - macroWindow) {
                uint256 startTime = nextTimestamp > block.timestamp - macroWindow
                    ? block.timestamp - macroWindow
                    : nextTimestamp;
                if (updatedAt >= macroAgoTargetTimestamp) {
                    sumOfPriceMacroWindowAgo += (startTime - updatedAt) * uint256(answer);
                } else {
                    sumOfPriceMacroWindowAgo +=
                        (startTime - macroAgoTargetTimestamp) *
                        uint256(answer);
                    break;
                }
            }

            nextTimestamp = updatedAt;
            roundId--;
        }

        priceOverMicroWindow = (sumOfPriceMicroWindow * (10**18)) / (microWindow * 10**decimals);
        priceOverMacroWindow = (sumOfPriceMacroWindow * (10**18)) / (macroWindow * 10**decimals);
        priceOneMacroWindowAgo =
            (sumOfPriceMacroWindowAgo * (10**18)) /
            (macroWindow * 10**decimals);
    }
}

