// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

interface ICapRewards {
    function collectReward (  ) external;
    function getClaimableReward (  ) external view returns ( uint256 );
}

