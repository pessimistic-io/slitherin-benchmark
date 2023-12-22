// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IRH2O {
    function allowance(
        address owner,
        address spender
    ) external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function burn(address from, uint amount) external;
}

