// SPDX-License-Identifier: BSD-4-Clause

pragma solidity ^0.8.13;

import { ChainlinkClient } from "./ChainlinkClient.sol";
import { AggregatorV2V3Interface } from "./AggregatorV2V3Interface.sol";
import { IPriceManager } from "./IPriceManager.sol";
import { Ownable } from "./Ownable.sol";
import { Address } from "./Address.sol";

contract PriceManager is IPriceManager, Ownable {
    using Address for address;

    string public assetPair; // BTCUSDT or ETHUSDT or BNBUSDT
    uint8 public roundIdChecks = 10;
    uint80 public numItr = 20;

    mapping(bytes32 => mapping(bytes32 => address)) public addressMap;

    function setNumItr(uint80 _itr) external onlyOwner {
        require(_itr > 0 && _itr <= 20, "Num Itr should be in 0 < numItr < 20");
        numItr = _itr;
    }

    function getPrice(
        bytes32 _underlying,
        bytes32 _strike,
        uint256 _timestamp
    ) public view override returns (uint256 price, uint8 decimals) {
        address aggregator = addressMap[_underlying][_strike];
        require(aggregator != address(0), "Chainlink: No aggregator");

        (uint80 roundId, , , , ) = AggregatorV2V3Interface(aggregator).latestRoundData();

        for (uint80 i = 1; i <= numItr; i++) {
            (, int256 answerI, , uint256 updatedAtI, ) = AggregatorV2V3Interface(aggregator).getRoundData(roundId - i);
            if (updatedAtI <= _timestamp && updatedAtI > 0) {
                price = uint256(answerI);
                break;
            }
        }

        decimals = AggregatorV2V3Interface(aggregator).decimals();
    }

    function setPairContract(
        bytes32 _underlying,
        bytes32 _strike,
        address _aggregator
    ) public override onlyOwner {
        require(_aggregator.isContract(), "Chainlink: Invalid aggregator");
        addressMap[_underlying][_strike] = _aggregator;

        emit AddAssetPairAggregator(_underlying, _strike, address(this), _aggregator);
    }
}

