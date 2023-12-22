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

import "./Checkpoints.sol";
import "./MembersRepo.sol";
import "./SharesRepo.sol";
import "./TopChain.sol";

interface IRegisterOfMembers {
    //##################
    //##    Event     ##
    //##################

    event SetVoteBase(bool indexed basedOnPar);

    event CapIncrease(uint indexed votingWeight, uint indexed paid, uint indexed par);

    event CapDecrease(uint indexed votingWeight, uint indexed paid, uint indexed par);

    event SetMaxQtyOfMembers(uint indexed max);

    event SetMinVoteRatioOnChain(uint indexed min);

    event SetAmtBase(bool indexed basedOnPar);

    event AddMember(uint256 indexed acct, uint indexed qtyOfMembers);

    event AddShareToMember(uint indexed seqOfShare, uint indexed acct);

    event RemoveShareFromMember(uint indexed seqOfShare, uint indexed acct);

    event ChangeAmtOfMember(
        uint indexed acct,
        uint indexed paid,
        uint indexed par,
        uint clean,
        bool increase
    );

    event AddMemberToGroup(uint indexed acct, uint indexed root);

    event RemoveMemberFromGroup(uint256 indexed acct, uint256 indexed root);

    event ChangeGroupRep(uint256 indexed orgRep, uint256 indexed newRep);

    //#################
    //##  Write I/O  ##
    //#################

    function setMaxQtyOfMembers(uint max) external;

    function setMinVoteRatioOnChain(uint min) external;

    function setVoteBase(bool _basedOnPar) external;

    function capIncrease(
        uint votingWeight, 
        uint paid, 
        uint par, 
        bool isIncrease
    ) external;

    function addMember(uint256 acct) external;

    function addShareToMember(
        SharesRepo.Share memory share
    ) external;

    function removeShareFromMember(
        SharesRepo.Share memory share
    ) external;

    function increaseAmtOfMember(
        uint acct,
        uint votingWeight,
        uint deltaPaid,
        uint deltaPar,
        uint deltaClean,
        bool isIncrease
    ) external ;

    function addMemberToGroup(uint acct, uint root) external;

    function removeMemberFromGroup(uint256 acct) external;

    // ##############
    // ##   Read   ##
    // ##############

    function isMember(uint256 acct) external view returns (bool);

    function qtyOfMembers() external view returns (uint);

    function membersList() external view returns (uint256[] memory);

    function sortedMembersList() external view returns (uint256[] memory);

    function qtyOfTopMembers() external view returns (uint);

    function topMembersList() external view returns (uint[] memory);

    // ---- Cap & Equity ----

    function ownersEquity() 
        external view 
        returns(Checkpoints.Checkpoint memory);

    function capAtDate(uint date)
        external view
        returns (Checkpoints.Checkpoint memory);

   function equityOfMember(uint256 acct)
        external view
        returns (Checkpoints.Checkpoint memory);

    function equityAtDate(uint acct, uint date) 
        external view returns(Checkpoints.Checkpoint memory);

    function votesInHand(uint256 acct)
        external view returns (uint64);

    function votesAtDate(uint256 acct, uint date)
        external view
        returns (uint64);

    function votesHistory(uint acct)
        external view 
        returns (Checkpoints.Checkpoint[] memory);

    // ---- ShareNum ----

    function qtyOfSharesInHand(uint acct)
        external view returns(uint);
    
    function sharesInHand(uint256 acct)
        external view
        returns (uint[] memory);

    // ---- Class ---- 

    function qtyOfSharesInClass(uint acct, uint class)
        external view returns(uint);

    function sharesInClass(uint256 acct, uint class)
        external view returns (uint[] memory);

    function isClassMember(uint256 acct, uint class)
        external view returns(bool);

    function classesBelonged(uint acct)
        external view returns(uint[] memory);

    function qtyOfClassMember(uint class)
        external view returns(uint);

    function getMembersOfClass(uint class)
        external view returns(uint256[] memory);
 
    // ---- TopChain ----

    function basedOnPar() external view returns (bool);

    function maxQtyOfMembers() external view returns (uint32);

    function minVoteRatioOnChain() external view returns (uint32);

    function totalVotes() external view returns (uint64);

    function controllor() external view returns (uint40);

    function tailOfChain() external view returns (uint40);

    function headOfQueue() external view returns (uint40);

    function tailOfQueue() external view returns (uint40);

    // ==== group ====

    function groupRep(uint256 acct) external view returns (uint40);

    function votesOfGroup(uint256 acct) external view returns (uint64);

    function deepOfGroup(uint256 acct) external view returns (uint256);

    function membersOfGroup(uint256 acct)
        external view
        returns (uint256[] memory);

    function qtyOfGroupsOnChain() external view returns (uint32);

    function qtyOfGroups() external view returns (uint256);

    function affiliated(uint256 acct1, uint256 acct2)
        external view
        returns (bool);

    // ==== snapshot ====

    function getSnapshot() external view returns (TopChain.Node[] memory, TopChain.Para memory);
}

