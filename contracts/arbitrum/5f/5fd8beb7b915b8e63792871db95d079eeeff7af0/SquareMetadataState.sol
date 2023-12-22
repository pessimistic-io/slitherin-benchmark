//SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "./Initializable.sol";
import "./EnumerableSetUpgradeable.sol";

import "./AdminableUpgradeable.sol";

abstract contract SquareMetadataState is Initializable, AdminableUpgradeable {
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

	EnumerableSetUpgradeable.AddressSet internal squares; //Square contracts to call methods

    string public baseURI;
    bool public revealed;

    function __SquareMetadataState_init() internal initializer {
        AdminableUpgradeable.__Adminable_init();
        revealed = false;
    }

}

struct RevealedPosition {
    uint256 x_;
    uint256 y_;
}
