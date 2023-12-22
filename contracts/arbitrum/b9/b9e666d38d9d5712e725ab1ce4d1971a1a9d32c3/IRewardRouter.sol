// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IRewardRouter {
    function claimFees() external;

    function compound() external;
}

