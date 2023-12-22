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

import "./ArrayUtils.sol";
import "./EnumerableSet.sol";
import "./SigsRepo.sol";

interface ISigPage {

    event CirculateDoc();

    //##################
    //##   Write I/O  ##
    //##################

    function circulateDoc() external;

    function setTiming(bool initPage, uint signingDays, uint closingDays) external;

    function addBlank(bool initPage, bool beBuyer, uint256 seqOfDeal, uint256 acct)
        external;

    function removeBlank(bool initPage, uint256 seqOfDeal, uint256 acct)
        external;

    function signDoc(bool initPage, uint256 caller, bytes32 sigHash) 
        external;    

    function regSig(uint256 signer, uint sigDate, bytes32 sigHash)
        external returns(bool flag);

    //##################
    //##   read I/O   ##
    //##################

    function getParasOfPage(bool initPage) external view 
        returns (SigsRepo.Signature memory);

    function circulated() external view returns(bool);

    function established() external view
        returns (bool flag);

    function getCirculateDate() external view returns(uint48);

    function getSigningDays() external view returns(uint16);

    function getClosingDays() external view returns(uint16);

    function getSigDeadline() external view returns(uint48);

    function getClosingDeadline() external view returns(uint48);

    function isBuyer(bool initPage, uint256 acct)
        external view returns(bool flag);

    function isSeller(bool initPage, uint256 acct)
        external view returns(bool flag);

    function isParty(uint256 acct)
        external view returns(bool flag);

    function isInitSigner(uint256 acct)
        external view returns (bool flag);


    function isSigner(uint256 acct)
        external view returns (bool flag);

    function getBuyers(bool initPage)
        external view returns (uint256[] memory buyers);

    function getSellers(bool initPage)
        external view returns (uint256[] memory sellers);

    function getParties() external view
        returns (uint256[] memory parties);

    function getSigOfParty(bool initParty, uint256 acct) external view
        returns (
            uint256[] memory seqOfDeals, 
            SigsRepo.Signature memory sig,
            bytes32 sigHash
        );

    function getSigsOfPage(bool initPage) external view
        returns (
            SigsRepo.Signature[] memory sigsOfBuyer, 
            SigsRepo.Signature[] memory sigsOfSeller
        );
}

