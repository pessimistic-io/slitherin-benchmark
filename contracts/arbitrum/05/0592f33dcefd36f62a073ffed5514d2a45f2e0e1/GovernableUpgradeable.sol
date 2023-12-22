// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./Initializable.sol";

contract GovernableUpgradeable is Initializable {
    address public gov;

    function __Governable_init() internal initializer {
        __Governable_init_unchained();
    }

    function __Governable_init_unchained() internal initializer {
        gov = msg.sender;
    }
    
    modifier onlyGov() {
        require(msg.sender == gov, "Governable: forbidden");
        _;
    }

    function setGov(address _gov) external onlyGov {
        gov = _gov;
    }
}

