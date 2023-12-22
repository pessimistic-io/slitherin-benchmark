// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Owned} from "./Owned.sol";
import {ERC20} from "./ERC20.sol";

contract YieldHandlerRegistry {
    mapping(address => address) public yieldHandlers;

    function setYieldHandler(address stablecoin, address handler) external {
        // Add access control as necessary
        yieldHandlers[stablecoin] = handler;
    }

    function getYieldHandler(address stablecoin) external view returns (address) {
        return yieldHandlers[stablecoin];
    }
}
