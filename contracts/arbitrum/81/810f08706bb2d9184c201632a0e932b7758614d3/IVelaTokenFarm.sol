// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IVelaTokenFarm {
    function depositVesting(uint256 _amount) external;
    function withdrawVesting() external;
    function withdraw(uint256 _pid, uint256 _amount) external;
    function claimable(address _account) external returns (uint256);
}
