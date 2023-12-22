//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./AdminableUpgradeable.sol";
import "./ITLDMetadata.sol";

abstract contract TLDMetadataState is Initializable, AdminableUpgradeable {
    function __TLDMetadataState_init() internal initializer {
        AdminableUpgradeable.__Adminable_init();
    }

    string public baseURI;
    string public provenance;
}

