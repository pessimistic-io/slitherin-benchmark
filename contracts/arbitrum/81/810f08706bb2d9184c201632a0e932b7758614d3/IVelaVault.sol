// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IVelaVault {
    function stake(
        address _account,
        address _token,
        uint256 _amount
    ) external;
    function unstake(
        address _tokenOut,
        uint256 _vlpAmount,
        address _receiver
    ) external;
}
