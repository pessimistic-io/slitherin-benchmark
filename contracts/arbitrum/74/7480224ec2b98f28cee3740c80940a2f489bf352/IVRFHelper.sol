pragma solidity ^0.8.0;
//SPDX-License-Identifier: MIT

// Interface for the randomizer.
contract IVRFHelper {
    function GetVRF(uint256) external view returns (uint256) {}
}
