// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {LibDiamond} from "./LibDiamond.sol";

import {EnumerableMap} from "./EnumerableMap.sol";
import {IERC20Extended} from "./IERC20Extended.sol";
import {IERC721Extended} from "./IERC721Extended.sol";

// using EnumerableMap for EnumerableMap.UintToAddressMap;

// Declare a set state variable
// EnumerableMap.UintToAddressMap private myMap;

struct AppStorage {
    bool diamondInitialized;
    IERC20Extended token;
    IERC721Extended nft;
    address DIAMOND_ADDRESS; // facet where getters are stored, need to add a setter too in game manager facet
    // dutch auction
    mapping(uint256 => uint256[]) petDna;
    // shop and items
    mapping(uint256 => uint256) itemPrice; //shop item id to price name this diff than items later
    mapping(uint256 => uint256) itemPoints;
    mapping(uint256 => string) itemName;
    mapping(uint256 => uint256) itemTimeExtension;
    mapping(uint256 => uint256) itemDelta; //item delta for pricing and selling
    mapping(uint256 => uint256) itemEquipExpires; //when long after consumed it expires
    mapping(uint256 => bool) itemIsSellable;
    mapping(uint256 => mapping(uint256 => uint256)) petItemExpires; // pet=>item=>expires time
    mapping(uint256 => uint256) itemSupply; //supply of items
    mapping(uint256 => EnumerableMap.UintToUintMap) itemsOwned; // items pet currently owns
    uint256 PRECISION;
    uint256 _tokenIds;
    uint256 _itemIds;
    uint256 la;
    uint256 lb;
    // pet properties
    mapping(uint256 => string) petName;
    mapping(uint256 => uint256) timeUntilStarving;
    mapping(uint256 => uint256) petScore;
    mapping(uint256 => uint256) timePetBorn;
    mapping(uint256 => uint256) lastAttackUsed;
    mapping(uint256 => uint256) lastAttacked;
    mapping(uint256 => uint256) stars;
    mapping(uint256 => uint256) petType;
    // vritual staking
    mapping(uint256 => uint256) ethOwed;
    mapping(uint256 => uint256) petRewardDebt;
    uint256 ethAccPerShare;
    uint256 totalScores;
    uint256 hasTheDiamond; //add this to the contractor instead
    mapping(uint256 => uint256) itemBought; //total bought to keep track of supply
    mapping(bytes32 => bool) nonces;
    uint256[] levelList;
}

library LibAppStorage {
    bytes32 internal constant DIAMOND_APP_STORAGE_POSITION =
        keccak256("diamond.app.storage");

    function appStorage() internal pure returns (AppStorage storage ds) {
        bytes32 position = DIAMOND_APP_STORAGE_POSITION;
        assembly {
            ds.slot := position
        }
    }

    // function diamondStorage() internal pure returns (AppStorage storage ds) {
    //     assembly {
    //         ds.slot := 0
    //     }
    // }

    // function abs(int256 x) internal pure returns (uint256) {
    //     return uint256(x >= 0 ? x : -x);
    // }
}

contract Modifiers {
    modifier onlyOwner() {
        LibDiamond.enforceIsContractOwner();
        _;
    }

    modifier isApproved(uint256 id) {
        AppStorage storage s = LibAppStorage.appStorage();

        require(
            s.nft.ownerOf(id) == msg.sender ||
                s.nft.getApproved(id) == msg.sender,
            "Not approved"
        );
        _;
    }
}
