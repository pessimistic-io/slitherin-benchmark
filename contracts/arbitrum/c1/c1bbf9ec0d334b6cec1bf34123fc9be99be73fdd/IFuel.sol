// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IFuel {
    function getBlockNumber() external returns (uint256);

    function mint(address to, uint256 amount) external returns (bool);

    function burn(uint256 amount) external;

    function balanceOf(address account) external returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function transferUnderlying(address to, uint256 amount) external returns (bool);

    function tokensToFragmentAtCurrentScalingFactor(uint256 value) external view returns (uint256);

    function fragmentToTokenAtCurrentScalingFactor(uint256 value) external view returns (uint256);
}

