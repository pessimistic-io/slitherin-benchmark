//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./ERC721Upgradeable.sol";
import "./CountersUpgradeable.sol";
import "./EnumerableSetUpgradeable.sol";

import "./IToadHousez.sol";
import "./AdminableUpgradeable.sol";
import "./IToadHousezMetadata.sol";

abstract contract ToadHousezState is Initializable, IToadHousez, ERC721Upgradeable, AdminableUpgradeable {

    using CountersUpgradeable for CountersUpgradeable.Counter;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

    CountersUpgradeable.Counter internal tokenIdCounter;

    EnumerableSetUpgradeable.AddressSet internal minters;

    IToadHousezMetadata public toadHousezMetadata;

    uint256 public amountBurned;

    uint256 public maxSupply;

    function __ToadHousezState_init() internal initializer {
        AdminableUpgradeable.__Adminable_init();
        ERC721Upgradeable.__ERC721_init("Toad Housez", "TDHSZ");

        tokenIdCounter.increment();

        maxSupply = 8888;
    }
}

