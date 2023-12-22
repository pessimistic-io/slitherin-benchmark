// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.20;

import {IMerkleDistributor} from "./IMerkleDistributor.sol";

interface IMerkleDistributorWithDeadline is IMerkleDistributor {
    function owner() external view returns (address);

    function endTime() external returns (uint256);

    function withdraw() external;
}

