// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IERC20Extended {
    function balanceOf(
        address tokenOwner
    ) external view returns (uint256 balance);

    function totalSupply() external view returns (uint256 supply);

    function transfer(
        address to,
        uint256 tokens
    ) external returns (bool success);

    function transferFrom(
        address from,
        address to,
        uint256 tokens
    ) external returns (bool success);

    function burn(uint256 amount) external;

    function burnFrom(address account, uint256 amount) external;
}
