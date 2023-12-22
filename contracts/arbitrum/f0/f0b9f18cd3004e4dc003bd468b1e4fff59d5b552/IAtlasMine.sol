// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IAtlasMine {

    // Returns the percentage of magic staked. 100% = 1 * 10**18
    function utilization() external view returns(uint256);
}
