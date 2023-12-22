// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IRamsesVoter {
    function gauges(address) external view returns (address);
}


