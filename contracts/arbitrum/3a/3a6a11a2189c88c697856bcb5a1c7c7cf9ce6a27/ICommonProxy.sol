//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.17;

/**
 * General interface for proxy.
 */
interface ICommonProxy {

    function logic() external view returns (address);
}
