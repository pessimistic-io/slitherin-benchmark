// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import { AggregatorV3Interface } from "./AggregatorV3Interface.sol";
import "./IInitializable.sol";
import "./UFixed18.sol";
import "./Token18.sol";

interface IKept is IInitializable {
    event KeeperCall(address indexed sender, uint256 gasUsed, UFixed18 multiplier, uint256 buffer, UFixed18 keeperFee);

    function ethTokenOracleFeed() external view returns (AggregatorV3Interface);
    function keeperToken() external view returns (Token18);
}

