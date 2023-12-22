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

import "./DealsRepo.sol";

interface IAntiDilution {

    struct Benchmark{
        uint16 classOfShare;
        uint32 floorPrice;
        EnumerableSet.UintSet obligors; 
    }

    struct Ruler {
        // classOfShare => Benchmark
        mapping(uint256 => Benchmark) marks;
        EnumerableSet.UintSet classes;        
    }

    // ################
    // ##   Write    ##
    // ################

    function addBenchmark(uint256 class, uint price) external;

    function removeBenchmark(uint256 class) external;

    function addObligor(uint256 class, uint256 obligor) external;

    function removeObligor(uint256 class, uint256 obligor) external;

    // ############
    // ##  read  ##
    // ############

    function isMarked(uint256 class) external view returns (bool flag);

    function getClasses() external view returns (uint256[] memory);

    function getFloorPriceOfClass(uint256 class) external view
        returns (uint32 price);

    function getObligorsOfAD(uint256 class)
        external view returns (uint256[] memory);

    function isObligor(uint256 class, uint256 acct) 
        external view returns (bool flag);

    function getGiftPaid(address ia, uint256 seqOfDeal, uint256 seqOfShare)
        external view returns (uint64 gift);

    function isTriggered(DealsRepo.Deal memory deal, uint seqOfShare) external view returns (bool);
}

