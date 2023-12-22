// SPDX-License-Identifier: UNLICENSED

/* *
 * Copyright (c) 2021-2023 LI LI @ JINGTIAN & GONGCHENG.
 *
 * This WORK is licensed under ComBoox SoftWare License 1.0, a copy of which 
 * can be obtained at:
 *         [https://github.com/paul-lee-attorney/comboox]
 *
 * THIS WORK IS PROVIDED ON AN "AS IS" BASIS, WITHOUT 
 * WARRANTIES OF ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED 
 * TO NON-INFRINGEMENT, MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE. IN NO 
 * EVENT SHALL ANY CONTRIBUTOR BE LIABLE TO YOU FOR ANY DAMAGES.
 *
 * YOU ARE PROHIBITED FROM DEPLOYING THE SMART CONTRACTS OF THIS WORK, IN WHOLE 
 * OR IN PART, FOR WHATEVER PURPOSE, ON ANY BLOCKCHAIN NETWORK THAT HAS ONE OR 
 * MORE NODES THAT ARE OUT OF YOUR CONTROL.
 * */

pragma solidity ^0.8.8;

import "./AccessControl.sol";
import "./IAlongs.sol";

contract Alongs is IAlongs, AccessControl {
    using LinksRepo for LinksRepo.Repo;

    LinksRepo.Repo private _repo;

    // ###############
    // ## Write I/O ##
    // ###############

    function addDragger(bytes32 rule, uint256 dragger) external onlyAttorney {
        _repo.addDragger(rule, dragger, _gk.getROM());
    }

    function removeDragger(uint256 dragger) external onlyAttorney {
        _repo.removeDragger(dragger);
    }

    function addFollower(uint256 dragger, uint256 follower) external onlyAttorney {
        _repo.addFollower(dragger, follower);
    }

    function removeFollower(uint256 dragger, uint256 follower) external onlyAttorney {
        _repo.removeFollower(dragger, follower);
    }

    // ################
    // ##  Read I/O  ##
    // ################

    function isDragger(uint256 dragger) external view returns (bool) {
        return _repo.isDragger(dragger, _gk.getROM());
    }

    function getLinkRule(uint256 dragger) external view returns (RulesParser.LinkRule memory) {
        return _repo.getLinkRule(dragger, _gk.getROM());
    }

    function isFollower(uint256 dragger, uint256 follower)
        external view returns (bool)
    {
        return _repo.isFollower(dragger, follower, _gk.getROM());
    }

    function getDraggers() external view returns (uint256[] memory) {
        return _repo.getDraggers();
    }

    function getFollowers(uint256 dragger) external view returns (uint256[] memory) {
        return _repo.getFollowers(dragger, _gk.getROM());
    }

    function priceCheck(
        DealsRepo.Deal memory deal
    ) public view returns (bool) {
        return _repo.priceCheck(deal, _gk.getROS(), _gk.getROM());
    }

    // #############
    // ##  Term   ##
    // #############

    function isTriggered(address ia, DealsRepo.Deal memory deal) public view returns (bool) {
        
        IRegisterOfMembers _rom = _gk.getROM();
        IRegisterOfAgreements _roa = _gk.getROA();
        
        if (_roa.getHeadOfFile(ia).state != uint8(FilesRepo.StateOfFile.Circulated))
            return false;

        if (deal.head.typeOfDeal ==
            uint8(DealsRepo.TypeOfDeal.CapitalIncrease) ||
            deal.head.typeOfDeal == uint8(DealsRepo.TypeOfDeal.PreEmptive)
        ) return false;

        if (!_repo.isDragger(deal.head.seller, _rom)) return false;

        RulesParser.LinkRule memory rule = 
            _repo.getLinkRule(deal.head.seller, _rom);

        if (rule.triggerDate > 0 && 
            (block.timestamp < rule.triggerDate ||
                block.timestamp >= rule.triggerDate + uint(rule.effectiveDays)*86400 ))
        return false;

        if (rule.triggerType == uint8(LinksRepo.TriggerTypeOfAlongs.NoConditions))
            return true;

        uint40 controllor = _rom.controllor();
        if (controllor != _rom.groupRep(deal.head.seller)) 
            return false;

        (uint40 newControllor, uint16 shareRatio) = _roa.mockResultsOfIA(ia);
        if (controllor == newControllor && shareRatio > rule.shareRatioThreshold) 
            return false;

        return priceCheck(deal);
    }
}

