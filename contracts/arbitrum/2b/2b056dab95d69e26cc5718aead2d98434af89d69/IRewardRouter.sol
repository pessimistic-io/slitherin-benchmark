// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface IRewardRouter { 
    function claimFees() external;
    function claimEsGmx() external;
    function stakeEsGmx(uint256 _amount) external;
}
