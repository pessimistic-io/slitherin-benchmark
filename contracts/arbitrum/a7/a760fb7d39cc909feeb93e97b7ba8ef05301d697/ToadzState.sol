//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./ERC721Upgradeable.sol";
import "./CountersUpgradeable.sol";
import "./EnumerableSetUpgradeable.sol";

import "./IToadz.sol";
import "./AdminableUpgradeable.sol";
import "./IToadzMetadata.sol";

abstract contract ToadzState is Initializable, IToadz, ERC721Upgradeable, AdminableUpgradeable {

    using CountersUpgradeable for CountersUpgradeable.Counter;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

    CountersUpgradeable.Counter internal tokenIdCounter;

    EnumerableSetUpgradeable.AddressSet internal minters;

    IToadzMetadata public toadzMetadata;

    uint256 public amountBurned;

    uint256 public maxSupply;

    function __ToadzState_init() internal initializer {
        AdminableUpgradeable.__Adminable_init();
        ERC721Upgradeable.__ERC721_init("Toadz", "TDZ");

        tokenIdCounter.increment();

        maxSupply = 8888;
    }
}

