pragma solidity ^0.8.0;
// SPDX-License-Identifier: MIT
interface ILftDaoVerifySignature {

    function verifyWithdraw(bytes memory data) external returns(address,uint256,uint256,uint256);

    function verifyStake(bytes memory data) external returns(address,uint256,uint256,uint256);

    function verifySwap(bytes memory data) external returns(address,uint256,uint256,uint256);
   
}
