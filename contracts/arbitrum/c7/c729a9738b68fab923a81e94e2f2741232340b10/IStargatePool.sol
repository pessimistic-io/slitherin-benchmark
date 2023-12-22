// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

interface IStargatePool {    

    function poolId() external view returns (uint256);

    function token() external view returns (address);

    function convertRate() external view returns (uint256);

    function balanceOf(address account) external view returns (uint);

    function approve(address spender, uint amount) external returns (bool);

    function amountLPtoLD(uint256 _amountLP) external view returns (uint256);
}

