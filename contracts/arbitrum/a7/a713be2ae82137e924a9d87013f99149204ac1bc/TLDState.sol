//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./ERC721Upgradeable.sol";
import "./CountersUpgradeable.sol";
import "./EnumerableSetUpgradeable.sol";

import "./ITLD.sol";
import "./AdminableUpgradeable.sol";
import "./ITLDMetadata.sol";

abstract contract TLDState is
    Initializable,
    ITLD,
    ERC721Upgradeable,
    AdminableUpgradeable
{
    using CountersUpgradeable for CountersUpgradeable.Counter;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

    CountersUpgradeable.Counter internal tokenIdCounter;

    EnumerableSetUpgradeable.AddressSet internal minters;

    ITLDMetadata public tldMetadata;

    uint256 public amountBurned;

    uint256 public maxSupply;

    function __TLDState_init() internal initializer {
        AdminableUpgradeable.__Adminable_init();
        ERC721Upgradeable.__ERC721_init("The Lost Donkeys", "TLD");
        maxSupply = 8005;
    }
}

