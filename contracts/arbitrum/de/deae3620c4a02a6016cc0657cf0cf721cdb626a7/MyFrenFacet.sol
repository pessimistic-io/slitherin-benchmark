// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {AppStorage, LibAppStorage, Modifiers} from "./LibAppStorage.sol";
import {BonkStorage, LibBonkStorage} from "./LibBonkStorage.sol";

import {EnumerableMap} from "./EnumerableMap.sol";
import {FixedPointMathLib} from "./FixedPointMathLib.sol";
import {SafeMath} from "./SafeMath.sol";

// use this contract to return all getters

contract MyFrenFacet is Modifiers {
    using EnumerableMap for EnumerableMap.UintToUintMap;
    using FixedPointMathLib for uint256;
    using SafeMath for uint256;

    /*//////////////////////////////////////////////////////////////
                        Game Getters
    //////////////////////////////////////////////////////////////*/

    function getDna(uint256 petId) public view returns (uint256[] memory) {
        AppStorage storage s = LibAppStorage.appStorage();
        return s.petDna[petId];
    }

    function rewardsDebt(uint256 petId) public view returns (uint256) {
        AppStorage storage s = LibAppStorage.appStorage();

        return s.petRewardDebt[petId];
    }

    function pendingEth(uint256 petId) public view returns (uint256) {
        AppStorage storage s = LibAppStorage.appStorage();

        uint256 _ethAccPerShare = s.ethAccPerShare;

        //petRewardDebt can sometimes be bigger by 1 wei do to several mulDivDowns so we do extra checks
        if (
            s.petScore[petId].mulDivDown(_ethAccPerShare, s.PRECISION) <
            s.petRewardDebt[petId]
        ) {
            return s.ethOwed[petId];
        } else {
            return
                (s.petScore[petId].mulDivDown(_ethAccPerShare, s.PRECISION))
                    .sub(s.petRewardDebt[petId])
                    .add(s.ethOwed[petId]);
        }
    }

    function petItems(
        uint256 _id,
        uint256 _itemId
    ) public view returns (uint256) {
        AppStorage storage s = LibAppStorage.appStorage();
        EnumerableMap.UintToUintMap storage itemsOwned = s.itemsOwned[_id];

        return itemsOwned.get(_itemId);
    }

    function getStatus(uint256 pet) public view returns (uint256 _health) {
        AppStorage storage s = LibAppStorage.appStorage();

        //  enum Status {
        //         HAPPY,
        //         HUNGRY,
        //         STARVING,
        //         DYING,
        //         DEAD
        //     }
        if (!isPetAlive(pet)) {
            return 4;
        }

        if (s.timeUntilStarving[pet] > block.timestamp + 16 hours) return 0;
        if (
            s.timeUntilStarving[pet] > block.timestamp + 12 hours &&
            s.timeUntilStarving[pet] < block.timestamp + 16 hours
        ) return 1;

        if (
            s.timeUntilStarving[pet] > block.timestamp + 8 hours &&
            s.timeUntilStarving[pet] < block.timestamp + 12 hours
        ) return 2;

        if (s.timeUntilStarving[pet] < block.timestamp + 8 hours) return 3;
    }

    function itemExists(uint256 itemId) public view returns (bool) {
        AppStorage storage s = LibAppStorage.appStorage();

        if (bytes(s.itemName[itemId]).length > 0) {
            return true;
        } else {
            return false;
        }
    }

    // check that Pet didn't starve
    function isPetAlive(uint256 _nftId) public view returns (bool) {
        AppStorage storage s = LibAppStorage.appStorage();

        uint256 _timeUntilStarving = s.timeUntilStarving[_nftId];
        if (_timeUntilStarving != 0 && _timeUntilStarving >= block.timestamp) {
            return true;
        } else {
            return false;
        }
    }

    function getItemInfo(
        uint256 _itemId
    )
        public
        view
        returns (
            string memory _name,
            uint256 _price,
            uint256 _sellPrice,
            uint256 _points,
            uint256 _timeExtension,
            uint256 _itemDelta,
            uint256 _itemEquipExpires,
            uint256 _bought,
            uint256 _supply,
            bool _itemIsSellable
        )
    {
        AppStorage storage s = LibAppStorage.appStorage();

        _name = s.itemName[_itemId];
        _price = s.itemPrice[_itemId];
        _sellPrice = ((s.itemPrice[_itemId] - s.itemDelta[_itemId]) * 90) / 100;
        _timeExtension = s.itemTimeExtension[_itemId];
        _points = s.itemPoints[_itemId];
        _itemDelta = s.itemDelta[_itemId];
        _itemEquipExpires = s.itemEquipExpires[_itemId];
        _bought = s.itemBought[_itemId];
        _supply = s.itemSupply[_itemId];
        _itemIsSellable = s.itemIsSellable[_itemId];
    }

    function getPetInfo(
        uint256 _nftId
    )
        public
        view
        returns (
            string memory _name,
            uint256 _status,
            uint256 _score,
            uint256 _level,
            uint256 _timeUntilStarving,
            uint256 _lastAttacked,
            uint256 _lastAttackUsed,
            address _owner,
            uint256 _rewards
        )
    {
        AppStorage storage s = LibAppStorage.appStorage();

        _name = s.petName[_nftId];
        _status = getStatus(_nftId);
        _score = s.petScore[_nftId];
        _level = level(_nftId);
        _timeUntilStarving = s.timeUntilStarving[_nftId];
        _lastAttacked = s.lastAttacked[_nftId];
        _lastAttackUsed = s.lastAttackUsed[_nftId];
        _owner = !isPetAlive(_nftId) && _score == 0
            ? address(0x0)
            : s.nft.ownerOf(_nftId);
        _rewards = pendingEth(_nftId);
    }

    // calculate level based on points
    function level(uint256 tokenId) public view returns (uint256 _level) {
        AppStorage storage s = LibAppStorage.appStorage();
        uint256 _score = s.petScore[tokenId] / 1e12;
        uint256[] memory levelList = s.levelList;

        if (levelList.length == 0) {
            return 0;
        }

        for(uint256 i = 0; i < levelList.length; i++) {
            if (i == levelList.length - 1) {
                _level = i;
            } else {
                if (_score >= levelList[i] && _score < levelList[i + 1]) {
                    _level = i;
                    break;
                }
            }
        }
    }

    function ethAccPerShare() public view returns (uint256) {
        AppStorage storage s = LibAppStorage.appStorage();

        return s.ethAccPerShare;
    }

    function totalScores() public view returns (uint256) {
        AppStorage storage s = LibAppStorage.appStorage();

        return s.totalScores;
    }

    function ethOwed(uint256 petId) public view returns (uint256) {
        AppStorage storage s = LibAppStorage.appStorage();

        return s.ethOwed[petId];
    }

    function petRewardDebt(uint256 petId) public view returns (uint256) {
        AppStorage storage s = LibAppStorage.appStorage();

        return s.petRewardDebt[petId];
    }

    function lastAttackUsed(uint256 petId) public view returns (uint256) {
        AppStorage storage s = LibAppStorage.appStorage();

        return s.lastAttackUsed[petId];
    }

    function lastAttacked(uint256 petId) public view returns (uint256) {
        AppStorage storage s = LibAppStorage.appStorage();

        return s.lastAttacked[petId];
    }

    function stars(uint256 petId) public view returns (uint256) {
        AppStorage storage s = LibAppStorage.appStorage();

        return s.stars[petId];
    }

    function petName(uint256 petId) public view returns (string memory) {
        AppStorage storage s = LibAppStorage.appStorage();

        return s.petName[petId];
    }

    function petScore(uint256 petId) public view returns (uint256) {
        AppStorage storage s = LibAppStorage.appStorage();

        return s.petScore[petId];
    }

    function timePetBorn(uint256 petId) public view returns (uint256) {
        AppStorage storage s = LibAppStorage.appStorage();

        return s.timePetBorn[petId];
    }

    function hasTheDiamond() public view returns (uint256) {
        AppStorage storage s = LibAppStorage.appStorage();

        return s.hasTheDiamond;
    }

    function timeUntilStarving(uint256 petId) public view returns (uint256) {
        AppStorage storage s = LibAppStorage.appStorage();

        return s.timeUntilStarving[petId];
    }

    function _sqrtu(uint256 x) private pure returns (uint128) {
        if (x == 0) return 0;
        else {
            uint256 xx = x;
            uint256 r = 1;
            if (xx >= 0x100000000000000000000000000000000) {
                xx >>= 128;
                r <<= 64;
            }
            if (xx >= 0x10000000000000000) {
                xx >>= 64;
                r <<= 32;
            }
            if (xx >= 0x100000000) {
                xx >>= 32;
                r <<= 16;
            }
            if (xx >= 0x10000) {
                xx >>= 16;
                r <<= 8;
            }
            if (xx >= 0x100) {
                xx >>= 8;
                r <<= 4;
            }
            if (xx >= 0x10) {
                xx >>= 4;
                r <<= 2;
            }
            if (xx >= 0x8) {
                r <<= 1;
            }
            r = (r + x / r) >> 1;
            r = (r + x / r) >> 1;
            r = (r + x / r) >> 1;
            r = (r + x / r) >> 1;
            r = (r + x / r) >> 1;
            r = (r + x / r) >> 1;
            r = (r + x / r) >> 1; // Seven iterations should be enough
            uint256 r1 = x / r;
            return uint128(r < r1 ? r : r1);
        }
    }

    // get all items for frontend
    struct ItemInfo {
        string name;
        uint256 price;
        uint256 sellPrice;
        uint256 points;
        uint256 timeExtension;
        uint256 itemDelta;
        uint256 itemEquipExpires;
        uint256 bought;
        uint256 supply;
        bool itemIsSellable;
    }

    function getItemsInfo()
        external
        view
        returns (ItemInfo[] memory itemsInfo)
    {
        AppStorage storage s = LibAppStorage.appStorage();
        itemsInfo = new ItemInfo[](s._itemIds);
        for (uint i = 0; i < itemsInfo.length; i++) {
            itemsInfo[i] = ItemInfo(
                s.itemName[i],
                s.itemPrice[i],
                ((s.itemPrice[i] - s.itemDelta[i]) * 90) / 100,
                s.itemTimeExtension[i],
                s.itemPoints[i],
                s.itemDelta[i],
                s.itemEquipExpires[i],
                s.itemBought[i],
                s.itemSupply[i],
                s.itemIsSellable[i]
            );
        }
    }

    // // add a mappingg later, for now simple getter
    function petCoinBalance(uint256 petId) external view returns (uint256) {
        AppStorage storage s = LibAppStorage.appStorage();
        if (((block.timestamp - s.timePetBorn[petId]) / 1 days) > 10) {
            return 10;
        } else {
            return 0;
        }
    }

    function petBonk(
        uint256 id
    )
        external
        view
        returns (uint256 _targetId, bytes32 _nonce, bytes32 _commit)
    {
        BonkStorage storage b = LibBonkStorage.bonkStorage();

        _targetId = b.petBonk[id].targetId;
        _nonce = b.petBonk[id].nonce;
        _commit = b.petBonk[id].commit;
    }

    function canBonk(uint256 petId) public view returns (bool) {
        return (lastAttackUsed(petId) + 15 minutes <= block.timestamp);
    }

    function canBeBonked(uint256 petId) public view returns (bool) {
        return (lastAttacked(petId) + 1 hours <= block.timestamp);
    }

    // get all pet items for frontend
    struct PetItem {
        string name;
        uint256 owned;
        uint256 itemEquipExpires;
        bool itemIsSellable;
    }

    function getPetItems(
        uint256 petId
    ) external view returns (PetItem[] memory itemInfo) {
        AppStorage storage s = LibAppStorage.appStorage();

        EnumerableMap.UintToUintMap storage itemsOwned = s.itemsOwned[petId];

        itemInfo = new PetItem[](s._itemIds);
        for (uint i = 0; i < itemInfo.length; i++) {
            (, uint256 totalOwned) = itemsOwned.tryGet(i);

            itemInfo[i] = PetItem(
                s.itemName[i],
                totalOwned,
                s.itemEquipExpires[i],
                s.itemIsSellable[i]
            );
        }
    }
}
