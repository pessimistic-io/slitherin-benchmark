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

import "./ILockUp.sol";

contract LockUp is ILockUp, AccessControl {
    using ArrayUtils for uint256[];
    using EnumerableSet for EnumerableSet.UintSet;

    // default expire date as “2105-09-19”
    uint48 constant _REMOTE_FUTURE = 4282732800;

    // lockers[0].keyHolders: ssnList;
    // seqOfShare => Locker
    mapping(uint256 => Locker) private _lockers;

    // ################
    // ## Write I/O  ##
    // ################

    function setLocker(uint256 seqOfShare, uint dueDate) external onlyAttorney {
        _lockers[seqOfShare].dueDate = uint48(dueDate) == 0 ? _REMOTE_FUTURE : uint48(dueDate);
        _lockers[0].keyHolders.add(seqOfShare);
    }

    function delLocker(uint256 seqOfShare) external onlyAttorney {
        if (_lockers[0].keyHolders.remove(seqOfShare)) {
            delete _lockers[seqOfShare];
        }
    }

    function addKeyholder(uint256 seqOfShare, uint256 keyholder) external onlyAttorney {
        require(seqOfShare != 0, "LU.addKeyholder: zero seqOfShare");
        _lockers[seqOfShare].keyHolders.add(keyholder);
    }

    function removeKeyholder(uint256 seqOfShare, uint256 keyholder) external onlyAttorney {
        require(seqOfShare != 0, "LU.removeKeyholder: zero seqOfShare");
        _lockers[seqOfShare].keyHolders.remove(keyholder);
    }

    // ################
    // ##  Read I/O  ##
    // ################

    function isLocked(uint256 seqOfShare) public view returns (bool) {
        return _lockers[0].keyHolders.contains(seqOfShare);
    }

    function getLocker(uint256 seqOfShare)
        external
        view
        returns (uint48 dueDate, uint256[] memory keyHolders)
    {
        dueDate = _lockers[seqOfShare].dueDate;
        keyHolders = _lockers[seqOfShare].keyHolders.values();
    }

    function lockedShares() external view returns (uint256[] memory) {
        return _lockers[0].keyHolders.values();
    }

    // ################
    // ##  Term      ##
    // ################

    function isTriggered(DealsRepo.Deal memory deal) external view returns (bool) {
 
        if (
            deal.head.typeOfDeal > 1 &&
            isLocked(deal.head.seqOfShare) &&
            _lockers[deal.head.seqOfShare].dueDate >= deal.head.closingDeadline
        ) return true;

        return false;
    }

    function _isExempted(uint256 seqOfShare, uint256[] memory agreedParties)
        private
        view
        returns (bool)
    {
        if (!isLocked(seqOfShare)) return true;

        Locker storage locker = _lockers[seqOfShare];

        uint256[] memory holders = locker.keyHolders.values();
        uint256 len = holders.length;

        if (len > agreedParties.length) {
            return false;
        } else {
            return holders.fullyCoveredBy(agreedParties);
        }
    }

    function isExempted(address ia, DealsRepo.Deal memory deal) external view returns (bool) {
        
        uint seqOfMotion = _gk.getROA().getHeadOfFile(ia).seqOfMotion;
               
        uint256[] memory parties = ISigPage(ia).getParties();

        BallotsBox.Case memory consentCase = _gk.getGMM().getCaseOfAttitude(seqOfMotion, 1);

        uint256[] memory supporters = 
            consentCase.voters.combine(consentCase.principals).merge(parties);

        return _isExempted(deal.head.seqOfShare, supporters);
    }

}

