// SPDX-License-Identifier: MIT

pragma solidity 0.8.12;

import "./MintableBaseTokenV2.sol";
import "./UUPSUpgradeable.sol";

contract sROSX is MintableBaseTokenV2, UUPSUpgradeable {
    uint256[50] private __gap;

    function initialize() public initializer {
        _initialize("Staked ROSX", "sROSX", 0);
    }


    function _authorizeUpgrade(address) internal override onlyOwner {
        
    }
}

