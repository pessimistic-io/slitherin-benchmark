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

import "./IMeetingMinutes.sol";

import "./OfficersRepo.sol";

interface IRegisterOfDirectors {

    //###################
    //##    events    ##
    //##################

    event AddPosition(bytes32 indexed snOfPos);

    event RemovePosition(uint256 indexed seqOfPos);

    event TakePosition(uint256 indexed seqOfPos, uint256 indexed caller);

    event QuitPosition(uint256 indexed seqOfPos, uint256 indexed caller);

    event RemoveOfficer(uint256 indexed seqOfPos);

    //#################
    //##  Write I/O  ##
    //#################

    function createPosition(bytes32 snOfPos) external;

    function updatePosition(OfficersRepo.Position memory pos) external;

    function removePosition(uint256 seqOfPos) external;

    function takePosition (uint256 seqOfPos, uint caller) external;

    function quitPosition (uint256 seqOfPos, uint caller) external; 

    function removeOfficer (uint256 seqOfPos) external;

    //################
    //##    Read    ##
    //################
    
    // ==== Positions ====

    function posExist(uint256 seqOfPos) external view returns (bool);

    function isOccupied(uint256 seqOfPos) external view returns (bool);

    function getPosition(uint256 seqOfPos) external view 
        returns (OfficersRepo.Position memory);

    // ==== Managers ====

    function isManager(uint256 acct) external view returns (bool);

    function getNumOfManagers() external view returns (uint256);    

    function getManagersList() external view returns (uint256[] memory);

    function getManagersPosList() external view returns(uint[] memory);

    // ==== Directors ====

    function isDirector(uint256 acct) external view returns (bool);

    function getNumOfDirectors() external view returns (uint256);

    function getDirectorsList() external view 
        returns (uint256[] memory);

    function getDirectorsPosList() external view 
        returns (uint256[] memory);

    // ==== Executives ====
    
    function hasPosition(uint256 acct, uint256 seqOfPos)
        external view returns(bool);

    function getPosInHand(uint256 acct) 
        external view returns (uint256[] memory);

    function getFullPosInfoInHand(uint acct) 
        external view returns (OfficersRepo.Position[] memory);

    function hasTitle(uint acct, uint title) 
        external returns (bool flag);

    function hasNominationRight(uint seqOfPos, uint acct) 
        external view returns (bool);

    // ==== seatsCalculator ====

    function getBoardSeatsOccupied(uint acct) external view 
        returns (uint256);

}

