//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./IWartlocksHallow.sol";
import "./AdminableUpgradeable.sol";
import "./IMagicStaking.sol";
import "./IWorld.sol";
import "./IBadgez.sol";
import "./IItemz.sol";
import "./IBugz.sol";

abstract contract WartlocksHallowState is Initializable, IWartlocksHallow, AdminableUpgradeable {

    event MagicRequiredToPowerCroakshireChanged(uint256 magicRequiredToPowerCroakshire);
    event ItemsToBurnChanged(uint256 itemsToBurn);
    event BurnableItemsAdded(uint128[] itemIds);
    event ItemsBurnt(BurnItemsParams burnItemParams);
    event HouseDesignCompleteChanged(bool isHouseDesignComplete);

    IMagicStaking public magicStaking;
    IWorld public world;
    IBadgez public badgez;
    IItemz public itemz;
    IBugz public bugz;

    uint256 public minimumBugzToStake;
    uint256 public magicRequiredToPowerCroakshire;
    uint256 public stakeMagicBadgeId;
    uint256 public stake100MagicBadgeId;

    uint256 public numberItemsToBurn;
    uint256 public currentItemsBurnt;
    uint256 public feedTheCauldronBadgeId;

    bool public isHouseDesignComplete;

    mapping(uint128 => bool) public itemIdToIsBurnable;

    function __WartlocksHallowState_init() internal initializer {
        AdminableUpgradeable.__Adminable_init();

        minimumBugzToStake = 1 ether;
        stakeMagicBadgeId = 9;
        stake100MagicBadgeId = 10;
        feedTheCauldronBadgeId = 11;

        magicRequiredToPowerCroakshire = 50_000 ether;
        emit MagicRequiredToPowerCroakshireChanged(magicRequiredToPowerCroakshire);

        numberItemsToBurn = 1000;
        emit ItemsToBurnChanged(1000);

        uint128[] memory _burnableItemz = new uint128[](4);
        _burnableItemz[0] = 1;
        _burnableItemz[1] = 3;
        _burnableItemz[2] = 4;
        _burnableItemz[3] = 5;
        for(uint256 i = 0; i < _burnableItemz.length; i++) {
            itemIdToIsBurnable[_burnableItemz[i]] = true;
        }
        emit BurnableItemsAdded(_burnableItemz);
    }
}

struct BurnItemsParams {
    uint128 itemId;
    uint120 amount;
}
