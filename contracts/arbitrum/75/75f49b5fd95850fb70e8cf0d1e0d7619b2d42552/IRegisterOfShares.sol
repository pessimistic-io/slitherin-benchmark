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

import "./SharesRepo.sol";
import "./LockersRepo.sol";

import "./IRegisterOfMembers.sol";

interface IRegisterOfShares {

    //##################
    //##    Event     ##
    //##################

    event IssueShare(bytes32 indexed shareNumber, uint indexed paid, uint indexed par);

    event PayInCapital(uint256 indexed seqOfShare, uint indexed amount);

    event SubAmountFromShare(uint256 indexed seqOfShare, uint indexed paid, uint indexed par);

    event DeregisterShare(uint256 indexed seqOfShare);

    event UpdatePriceOfPaid(uint indexed seqOfShare, uint indexed newPrice);

    event UpdatePaidInDeadline(uint256 indexed seqOfShare, uint indexed paidInDeadline);

    event DecreaseCleanPaid(uint256 indexed seqOfShare, uint indexed paid);

    event IncreaseCleanPaid(uint256 indexed seqOfShare, uint indexed paid);

    event SetPayInAmt(bytes32 indexed headSn, bytes32 indexed hashLock);

    event WithdrawPayInAmt(uint indexed seqOfShare, uint indexed amount);

    event IncreaseEquityOfClass(bool indexed isIncrease, uint indexed class, uint indexed amt);

    //##################
    //##  Write I/O   ##
    //##################

    function issueShare(bytes32 shareNumber, uint payInDeadline, uint paid, uint par) external;

    function addShare(SharesRepo.Share memory share) external;

    function setPayInAmt(uint seqOfShare, uint amt, uint expireDate, bytes32 hashLock) external;

    function requestPaidInCapital(bytes32 hashLock, string memory hashKey) external;

    function withdrawPayInAmt(bytes32 hashLock, uint seqOfShare) external;

    function payInCapital(uint seqOfShare, uint amt) external;

    function transferShare(
        uint256 seqOfShare,
        uint paid,
        uint par,
        uint to,
        uint priceOfPaid,
        uint priceOfPar
    ) external;

    function decreaseCapital(uint256 seqOfShare, uint paid, uint par) external;

    // ==== CleanPaid ====

    function decreaseCleanPaid(uint256 seqOfShare, uint paid) external;

    function increaseCleanPaid(uint256 seqOfShare, uint paid) external;

    // ==== State & PaidInDeadline ====

    function updatePriceOfPaid(uint seqOfShare, uint newPrice) external;

    function updatePaidInDeadline(uint256 seqOfShare, uint paidInDeadline) external;

    // ==== EquityOfClass ====

    function increaseEquityOfClass(
        bool isIncrease,
        uint classOfShare,
        uint deltaPaid,
        uint deltaPar,
        uint deltaCleanPaid
    ) external;

    // ##################
    // ##   Read I/O   ##
    // ##################

    function counterOfShares() external view returns (uint32);

    function counterOfClasses() external view returns (uint16);

    // ==== SharesRepo ====

    function isShare(
        uint256 seqOfShare
    ) external view returns (bool);

    function getShare(
        uint256 seqOfShare
    ) external view returns (
        SharesRepo.Share memory
    );

    function getQtyOfShares() external view returns (uint);

    function getSeqListOfShares() external view returns (uint[] memory);

    function getSharesList() external view returns (SharesRepo.Share[] memory);

    // ---- Class ----    

    function getQtyOfSharesInClass(
        uint classOfShare
    ) external view returns (uint);

    function getSeqListOfClass(
        uint classOfShare
    ) external view returns (uint[] memory);

    function getInfoOfClass(
        uint classOfShare
    ) external view returns (SharesRepo.Share memory);

    function getSharesOfClass(
        uint classOfShare
    ) external view returns (SharesRepo.Share[] memory);

    // ==== PayInCapital ====

    function getLocker(
        bytes32 hashLock
    ) external view returns (LockersRepo.Locker memory);

    function getLocksList() external view returns (bytes32[] memory);
}

