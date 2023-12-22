//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./EnumerableSetUpgradeable.sol";
import "./ERC721HolderUpgradeable.sol";

import "./IToadz.sol";
import "./IWorld.sol";
import "./AdminableUpgradeable.sol";
import "./IHuntingGrounds.sol";
import "./ICrafting.sol";

abstract contract WorldState is Initializable, IWorld, ERC721HolderUpgradeable, AdminableUpgradeable {

    event ToadLocationChanged(uint256[] _tokenIds, address _owner, Location _newLocation);

    IToadz public toadz;
    IHuntingGrounds public huntingGrounds;
    ICrafting public crafting;

    mapping(uint256 => TokenInfo) internal tokenIdToInfo;

    mapping(address => EnumerableSetUpgradeable.UintSet) internal ownerToStakedTokens;

    function __WorldState_init() internal initializer {
        AdminableUpgradeable.__Adminable_init();
        ERC721HolderUpgradeable.__ERC721Holder_init();
    }
}

// Be careful of changing as this is stored in storage.
struct TokenInfo {
    address owner;
    Location location;
}
