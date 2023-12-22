// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {UUPSUpgradeable} from "./UUPSUpgradeable.sol";

contract Reserve is UUPSUpgradeable {
    address public governor;

    function initialize(address governor_) external {
        require(governor == address(0));
        governor = governor_;
    }

    function _authorizeUpgrade(address) internal view override {
        require(msg.sender == governor, "Aloe: only governor");
    }
}

