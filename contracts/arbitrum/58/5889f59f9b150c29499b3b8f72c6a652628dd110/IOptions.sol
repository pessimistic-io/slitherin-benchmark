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

import "./OptionsRepo.sol";
import "./EnumerableSet.sol";

interface IOptions {
    
    // ################
    // ## Write I/O ##
    // ################

    function createOption(
        bytes32 snOfOpt,
        bytes32 snOfCond,
        uint rightholder,
        uint paid,
        uint par
    ) external returns (OptionsRepo.Head memory head); 

    function delOption(uint256 seqOfOpt) external returns(bool flag);

    function addObligorIntoOpt(
        uint256 seqOfOpt,
        uint256 obligor
    ) external returns (bool flag);

    function removeObligorFromOpt(
        uint256 seqOfOpt,
        uint256 obligor
    ) external returns (bool flag);


    // ################
    // ##  Read I/O  ##
    // ################

    // ==== Option ====

    function counterOfOptions() external view returns (uint32);

    function qtyOfOptions() external view returns (uint);

    function isOption(uint256 seqOfOpt) external view returns (bool);

    function getOption(uint256 seqOfOpt) external view
        returns (OptionsRepo.Option memory option); 

    function getAllOptions() external view returns (OptionsRepo.Option[] memory);

    // ==== Obligor ====

    function isObligor(uint256 seqOfOpt, uint256 acct) external 
        view returns (bool); 

    function getObligorsOfOption(uint256 seqOfOpt) external view
        returns (uint256[] memory);

    // ==== snOfOpt ====
    function getSeqList() external view returns(uint[] memory);

}

