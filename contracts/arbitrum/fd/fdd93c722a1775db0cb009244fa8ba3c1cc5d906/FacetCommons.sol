// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {AppStorage, LibAppStorage, Modifiers} from "./LibAppStorage.sol";
import {ReferralStorage, LibReferralStorage} from "./LibReferralStorage.sol";

import {MyFrenFacet} from "./MyFrenFacet.sol";
import {IMyFren} from "./IMyFren.sol";

import {SafeTransferLib} from "./SafeTransferLib.sol";

import {FixedPointMathLib} from "./FixedPointMathLib.sol";

import {EnumerableMap} from "./EnumerableMap.sol";

abstract contract FacetCommons {
    using SafeTransferLib for address payable;
    using FixedPointMathLib for uint256;

    using EnumerableMap for EnumerableMap.UintToUintMap;
    
    error CanNotUnequip();

    event RedeemRewards(uint256 indexed petId, uint256 reward);

    function _redeem(uint256 petId, address _to) internal {
        AppStorage storage s = LibAppStorage.appStorage();

        uint256 pending = myFrenFacet().pendingEth(petId);

        s.totalScores -= s.petScore[petId];
        s.petScore[petId] = 0;
        s.ethOwed[petId] = 0;
        s.petRewardDebt[petId] = 0;

        payable(_to).safeTransferETH(pending);

        emit RedeemRewards(petId, pending);
    }

    function myFrenFacet() internal view returns (MyFrenFacet fpFacet) {
        AppStorage storage s = LibAppStorage.appStorage();

        fpFacet = MyFrenFacet(s.DIAMOND_ADDRESS);
    }

    function equipItem(uint256 petId, uint256 itemId) internal {
        AppStorage storage s = LibAppStorage.appStorage();

        require(s.itemBought[itemId] < s.itemSupply[itemId], "sold out");

        s.itemBought[itemId] += 1;

        EnumerableMap.UintToUintMap storage itemsOwned = s.itemsOwned[petId];

        (, uint256 totalOwned) = itemsOwned.tryGet(itemId);

        itemsOwned.set(itemId, totalOwned + 1);

        // when expires
        s.petItemExpires[petId][itemId] = s.itemEquipExpires[itemId] > 0
            ? block.timestamp + s.itemEquipExpires[itemId]
            : 0;

        //add delta
        s.itemPrice[itemId] += s.itemDelta[itemId];

        //lower from supply
    }

    function updatePointsAndRewards(uint256 _petId, uint256 _points) internal {
        AppStorage storage s = LibAppStorage.appStorage();

        if (s.petScore[_petId] > 0) {
            s.ethOwed[_petId] = myFrenFacet().pendingEth(_petId);
        }

        s.petScore[_petId] += _points;

        s.petRewardDebt[_petId] = s.petScore[_petId].mulDivDown(
            s.ethAccPerShare,
            s.PRECISION
        );

        s.totalScores += _points;
    }

     function distributeToRef(uint256 _petId, uint256 refAmt) internal {
        ReferralStorage storage r = LibReferralStorage.referralStorage();
        AppStorage storage s = LibAppStorage.appStorage();

        address addr = r.petToRef[_petId];

        if (addr == address(0)) {
            s.token.transfer(
                0xFF0C532FDB8Cd566Ae169C1CB157ff2Bdc83E105,
                refAmt
            );
        } else {
            s.token.transfer(addr, refAmt);
        }
    }

    // unequip an item
    function _unequipItem(uint256 petId, uint256 itemId) internal {
        AppStorage storage s = LibAppStorage.appStorage();

        EnumerableMap.UintToUintMap storage itemsOwned = s.itemsOwned[petId];

        // credit to user
        (, uint256 totalOwned) = itemsOwned.tryGet(itemId);

        if (totalOwned == 0) revert CanNotUnequip();

        itemsOwned.set(itemId, totalOwned - 1);

        s.itemBought[itemId] -= 1;
        s.itemPrice[itemId] -= s.itemDelta[itemId];
    }
}
