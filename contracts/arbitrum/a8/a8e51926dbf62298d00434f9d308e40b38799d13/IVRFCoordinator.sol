// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./VRFCoordinatorV2Interface.sol";

interface IVRFCoordinatorV2 is VRFCoordinatorV2Interface {
    function getFeeConfig()
        external
        view
        returns (uint32, uint32, uint32, uint32, uint32, uint24, uint24, uint24, uint24);
}

