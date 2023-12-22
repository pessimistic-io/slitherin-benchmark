//SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "./Initializable.sol";
import "./EnumerableSetUpgradeable.sol";

import "./AdminableUpgradeable.sol";
import "./DonkeBoardMetadata.sol";

abstract contract DonkeBoardMetadataState is
    Initializable,
    AdminableUpgradeable
{
    string public baseURI;
    string public provenance;

    function __DonkeBoardMetadataState_init() internal initializer {
        AdminableUpgradeable.__Adminable_init();
    }
}

