// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.6;

interface IRamsesVoter {
    function gauges(address) external view returns (address);
}


