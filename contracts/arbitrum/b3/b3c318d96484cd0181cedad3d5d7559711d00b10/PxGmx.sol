// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {PxERC20} from "./PxERC20.sol";

contract PxGmx is PxERC20 {
    /**
        @param  _pirexRewards  address  PirexRewards contract address
    */
    constructor(address _pirexRewards)
        PxERC20(_pirexRewards, "Pirex GMX", "pxGMX", 18)
    {}

    /**
        @notice Disable pxGMX burning
    */
    function burn(address, uint256) external override {}
}

