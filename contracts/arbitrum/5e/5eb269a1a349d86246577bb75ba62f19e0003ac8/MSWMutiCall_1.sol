// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "./IERC20.sol";
import {IMA} from "./IMA_1.sol";
import {IMSW} from "./IMSW_1.sol";
import {INftMinning} from "./INftMinning.sol";
import "./AddressUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./Initializable.sol";

contract MSWMutiCall_1 is OwnableUpgradeable {
    IMSW public mswUnions;
    INftMinning public minning;
    IMA public kun;

    // init
    function init() public initializer {
        __Context_init_unchained();
        __Ownable_init_unchained();
        // test
        // mswUnions = IMSW(0xE2B0D6C2bFf5e40563f48e94000B96d36F373942);
        // minning = INftMinning(0xE2B0D6C2bFf5e40563f48e94000B96d36F373942);

        // main test
        mswUnions = IMSW(0x975AEB96c3C610fC97FEcfC681AD899e380C5CFb);
        minning = INftMinning(0x4E27847BccA57d3B607c7991c4B06f9b18c3E4c8);
    }

    function setUnion(address union_) public onlyOwner {
        mswUnions = IMSW(union_);
    }

    function setMinning(address minning_) public onlyOwner {
        minning = INftMinning(minning_);
    }

    function setKun(address kun_) public onlyOwner {
        kun = IMA(kun_);
    }

    function frontEndUnions(
        address user
    )
        external
        view
        returns (
            uint _ownUnions,
            string memory _url,
            uint _uions,
            uint _ownUnionsLv
        )
    {
        _ownUnions = minning.unionOwner(user);
        if (_ownUnions != 0) {
            _url = mswUnions.tokenURI(_ownUnions);
        }
        _uions = minning.checkUserUnions(user);
        _ownUnionsLv = minning.checkUnionLv(_ownUnions);

        // (tokenIds, cardIds) = mswUnions.tokenOfOwnerForAll(user);
    }

    function frontEndJions(
        uint uid_
    ) external view returns (uint[4] memory unions) {
        (, unions[1], unions[2], , unions[3], , , , , , , ) = minning
            .unionsInfo(uid_);
    }

    function frontEndDeposited(
        address user
    )
        external
        view
        returns (
            uint[] memory ids,
            uint[] memory power,
            uint[] memory time,
            uint[] memory lv
        )
    {
        ids = minning.checkUserKunIdList(user);
        power = new uint[](ids.length);
        time = new uint[](ids.length);
        lv = new uint[](ids.length);
        for (uint i; i < ids.length; i++) {
            (lv[i], , ) = kun.characters(ids[i]);
            (, , power[i], time[i]) = minning.kunInfo(ids[i]);
        }
    }

    function frontEndDao(
        uint uid_
    )
        public
        view
        returns (
            address owner,
            uint[2] memory tax,
            uint[2] memory getax,
            uint[2] memory dao
        )
    {
        (owner, , , , , , tax[0], , getax[0], , , dao[0]) = minning.unionsInfo(
            uid_
        );
        tax[1] = minning.checkTax(uid_);
        getax[1] = minning.checkGeTax(uid_);
        dao[1] = minning.checkDaoBonus(uid_);
    }

    function frontEndKun(
        address user
    ) external view returns (uint[] memory kunIds, uint[] memory lv) {
        kunIds = kun.tokensOfOwner(user);

        uint len = kunIds.length;
        // kunIds = new uint[](len);
        lv = new uint[](len);

        for (uint i; i < len; i++) {
            (lv[i], , ) = kun.characters(kunIds[i]);
        }
    }

    function frontEndNftMinning(
        address user
    ) external view returns (uint[2] memory uints) {
        (, uints[0], , , , ) = minning.userInfo(user);
        uints[1] = minning.checkUserReward(user);
    }
}

