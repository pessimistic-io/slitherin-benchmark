//SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "./Initializable.sol";
import "./ERC721Upgradeable.sol";
import "./EnumerableSetUpgradeable.sol";

import "./IDonkeBoard.sol";
import "./AdminableUpgradeable.sol";
import "./IDonkeBoardMetadata.sol";

abstract contract DonkeBoardState is
    Initializable,
    IDonkeBoard,
    ERC721Upgradeable,
    AdminableUpgradeable
{
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

    EnumerableSetUpgradeable.AddressSet internal minters;

    IDonkeBoardMetadata public donkeBoardMetadata;

    uint256 public amountBurned;
    uint256 public maxSupply;

    function __DonkeBoardState_init() internal initializer {
        AdminableUpgradeable.__Adminable_init();
        ERC721Upgradeable.__ERC721_init("The Donkeboards", "DONKEBOARD");
        maxSupply = 8055;
    }
}

