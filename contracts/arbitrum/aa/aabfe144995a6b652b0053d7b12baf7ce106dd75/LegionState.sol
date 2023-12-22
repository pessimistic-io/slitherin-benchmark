//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC721URIStorageUpgradeable.sol";
import "./CountersUpgradeable.sol";
import "./Initializable.sol";

import "./AdminableUpgradeable.sol";
import "./ILegion.sol";
import "./ILegionMetadataStore.sol";

abstract contract LegionState is Initializable, ILegion, AdminableUpgradeable, ERC721URIStorageUpgradeable {

    using CountersUpgradeable for CountersUpgradeable.Counter;

    CountersUpgradeable.Counter internal tokenIdCounter;

    ILegionMetadataStore public legionMetadataStore;

    function __LegionState_init() internal initializer {
        AdminableUpgradeable.__Adminable_init();
        ERC721URIStorageUpgradeable.__ERC721URIStorage_init();
        ERC721Upgradeable.__ERC721_init("LEGION", "LGN");

        // Start at 1.
        tokenIdCounter.increment();
    }
}
