// SPDX-License-Identifier: MIT

pragma solidity ^0.8.11;

import "./Initializable.sol";

contract GovernableUpgradeable is Initializable {
    address public gov;

    function __Governable_init() internal onlyInitializing {
        __Governable_init_unchained();
    }

    function __Governable_init_unchained() internal onlyInitializing {
        gov = msg.sender;
    }

    modifier onlyGov() {
        require(msg.sender == gov, "Governable: forbidden");
        _;
    }

    function setGov(address _gov) external onlyGov {
        require(_gov != address(0), "Governable: invalid address");
        gov = _gov;
    }

    uint256[49] private __gap;
}

