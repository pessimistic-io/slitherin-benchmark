// SPDX-License-Identifier: MIT
pragma solidity >=0.6.12;

interface IRebateEstimator {
    function getRebate(address account) external view returns (uint64);
}
