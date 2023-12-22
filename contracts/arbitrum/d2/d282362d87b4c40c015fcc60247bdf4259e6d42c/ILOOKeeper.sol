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

interface ILOOKeeper {

    //###############
    //##   Write   ##
    //###############

    function regInvestor(
        uint userNo,
        uint groupRep,
        bytes32 idHash
    ) external;

    function approveInvestor(
        uint userNo,
        uint caller,
        uint seqOfLR
    ) external;

    function revokeInvestor(
        uint userNo,
        uint caller,
        uint seqOfLR
    ) external;

    function placeInitialOffer(
        uint caller,
        uint classOfShare,
        uint execHours,
        uint paid,
        uint price,
        uint seqOfLR
    ) external;

    function withdrawInitialOffer(
        uint caller,
        uint classOfShare,
        uint seqOfOrder,
        uint seqOfLR
    ) external;

    function placeSellOrder(
        uint caller,
        uint seqOfClass,
        uint execHours,
        uint paid,
        uint price,
        uint seqOfLR,
        bool sortFromHead
    ) external;

    function withdrawSellOrder(
        uint caller,
        uint classOfShare,
        uint seqOfOrder
    ) external;

    function placeBuyOrder(
        uint caller,
        uint classOfShare,
        uint paid,
        uint price,
        uint msgValue
    ) external;

}

