//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./ImbuedSoulState.sol";

abstract contract ImbuedSoulContracts is Initializable, ImbuedSoulState {

    function __ImbuedSoulContracts_init() internal initializer {
        ImbuedSoulState.__ImbuedSoulState_init();
    }

    function compareStrings(string memory a, string memory b) internal pure returns (bool) {
        return (keccak256(abi.encodePacked((a))) == keccak256(abi.encodePacked((b))));
    }
}
