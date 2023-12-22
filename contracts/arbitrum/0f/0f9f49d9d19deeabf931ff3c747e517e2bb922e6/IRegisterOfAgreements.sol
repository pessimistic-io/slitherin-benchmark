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

import "./IFilesFolder.sol";
import "./IInvestmentAgreement.sol";

import "./DTClaims.sol";
import "./FRClaims.sol";
import "./TopChain.sol";

interface IRegisterOfAgreements is IFilesFolder {

    //#################
    //##    Event    ##
    //#################

    event ClaimFirstRefusal(address indexed ia, uint256 indexed seqOfDeal, uint256 indexed caller);

    event AcceptAlongClaims(address indexed ia, uint indexed seqOfDeal);

    event ExecAlongRight(address indexed ia, bytes32 indexed snOfDTClaim, bytes32 sigHash);

    event ComputeFirstRefusal(address indexed ia, uint256 indexed seqOfDeal);

    //#################
    //##  Write I/O  ##
    //#################

    // ======== RegisterOfAgreements ========

    function claimFirstRefusal(
        address ia,
        uint256 seqOfDeal,
        uint256 caller,
        bytes32 sigHash
    ) external;

    function computeFirstRefusal(
        address ia,
        uint256 seqOfDeal
    ) external returns (FRClaims.Claim[] memory output);

    function execAlongRight(
        address ia,
        bool dragAlong,
        uint256 seqOfDeal,
        uint256 seqOfShare,
        uint paid,
        uint par,
        uint256 caller,
        bytes32 sigHash
    ) external;

    function acceptAlongClaims(
        address ia, 
        uint seqOfDeal
    ) external returns(DTClaims.Claim[] memory);

    function createMockOfIA(address ia) external;

    function mockDealOfSell (address ia, uint seller, uint amount) external; 

    function mockDealOfBuy (address ia, uint buyer, uint groupRep, uint amount) external;

    //################
    //##    Read    ##
    //################

    // ==== FR Claims ====

    function hasFRClaims(address ia, uint seqOfDeal) external view returns (bool);

    function isFRClaimer(address ia, uint256 acct) external returns (bool);

    function getSubjectDealsOfFR(address ia) external view returns(uint[] memory);

    function getFRClaimsOfDeal(address ia, uint256 seqOfDeal)
        external view returns(FRClaims.Claim[] memory);

    function allFRClaimsAccepted(address ia) external view returns (bool);

    // ==== DT Claims ====

    function hasDTClaims(address ia, uint256 seqOfDeal) 
        external view returns(bool);

    function getSubjectDealsOfDT(address ia)
        external view returns(uint256[] memory);

    function getDTClaimsOfDeal(address ia, uint256 seqOfDeal)
        external view returns(DTClaims.Claim[] memory);

    function getDTClaimForShare(address ia, uint256 seqOfDeal, uint256 seqOfShare)
        external view returns(DTClaims.Claim memory);

    function allDTClaimsAccepted(address ia) external view returns(bool);

    // ==== Mock Results ====

    function mockResultsOfIA(address ia) 
        external view 
        returns (uint40 controllor, uint16 ratio);

    function mockResultsOfAcct(address ia, uint256 acct) 
        external view 
        returns (uint40 groupRep, uint16 ratio);

    // ==== AllClaimsAccepted ====

    function allClaimsAccepted(address ia) external view returns(bool);

}

