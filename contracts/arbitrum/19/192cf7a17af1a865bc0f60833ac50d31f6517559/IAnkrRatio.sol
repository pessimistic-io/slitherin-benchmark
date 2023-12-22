// SPDX-License-Identifier: MIT

pragma solidity ^0.8.14;

/** 
 *  ankrMATIC interface.
 */
interface IAnkrRatio {
    function ratio() external view returns (uint256);
}
