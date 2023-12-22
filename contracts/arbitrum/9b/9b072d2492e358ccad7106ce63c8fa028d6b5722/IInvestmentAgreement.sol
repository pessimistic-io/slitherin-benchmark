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

import "./SwapsRepo.sol";
import "./DealsRepo.sol";

import "./ISigPage.sol";

interface IInvestmentAgreement is ISigPage {

    //##################
    //##    Event     ##
    //##################

    event RegDeal(uint indexed seqOfDeal);

    event ClearDealCP(
        uint256 indexed seq,
        bytes32 indexed hashLock,
        uint indexed closingDeadline
    );

    event CloseDeal(uint256 indexed seq, string indexed hashKey);

    event TerminateDeal(uint256 indexed seq);
    
    event CreateSwap(uint seqOfDeal, bytes32 snOfSwap);

    event PayOffSwap(uint seqOfDeal, uint seqOfSwap, uint msgValue);

    event TerminateSwap(uint seqOfDeal, uint seqOfSwap);

    event PayOffApprovedDeal(uint seqOfDeal, uint msgValue);

    //##################
    //##  Write I/O  ##
    //##################

    // ======== InvestmentAgreement ========

    function addDeal(
        bytes32 sn,
        uint buyer,
        uint groupOfBuyer,
        uint paid,
        uint par
    ) external;

    function regDeal(DealsRepo.Deal memory deal) external returns(uint16 seqOfDeal);

    function delDeal(uint256 seq) external;

    function lockDealSubject(uint256 seq) external returns (bool flag);

    function releaseDealSubject(uint256 seq) external returns (bool flag);

    function clearDealCP( uint256 seq, bytes32 hashLock, uint closingDeadline) external;

    function closeDeal(uint256 seq, string memory hashKey)
        external returns (bool flag);

    function directCloseDeal(uint256 seq) external returns (bool flag);

    function terminateDeal(uint256 seqOfDeal) external returns(bool);

    function takeGift(uint256 seq) external returns(bool);

    function finalizeIA() external;

    // ==== Swap ====

    function createSwap (
        uint seqOfMotion,
        uint seqOfDeal,
        uint paidOfTarget,
        uint seqOfPledge,
        uint caller
    ) external returns(SwapsRepo.Swap memory swap);

    function payOffSwap(
        uint seqOfMotion,
        uint seqOfDeal,
        uint seqOfSwap,
        uint msgValue,
        uint centPrice
    ) external returns(SwapsRepo.Swap memory swap);

    function terminateSwap(
        uint seqOfMotion,
        uint seqOfDeal,
        uint seqOfSwap
    ) external returns (SwapsRepo.Swap memory swap);

    function payOffApprovedDeal(
        uint seqOfDeal,
        uint msgValue,
        uint caller
    ) external returns (bool flag);

    function requestPriceDiff(
        uint seqOfDeal,
        uint seqOfShare
    ) external;

    //  #####################
    //  ##     Read I/O    ##
    //  #####################

    // ======== InvestmentAgreement ========
    function getTypeOfIA() external view returns (uint8);

    function getDeal(uint256 seq) external view returns (DealsRepo.Deal memory);

    function getSeqList() external view returns (uint[] memory);

    // ==== Swap ====

    function getSwap(uint seqOfDeal, uint256 seqOfSwap)
        external view returns (SwapsRepo.Swap memory);

    function getAllSwaps(uint seqOfDeal)
        external view returns (SwapsRepo.Swap[] memory);

    function allSwapsClosed(uint seqOfDeal)
        external view returns (bool);

    function checkValueOfSwap(uint seqOfDeal, uint seqOfSwap)
        external view returns(uint);

    function checkValueOfDeal(uint seqOfDeal)
        external view returns (uint);

}

