// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IPositionManager {
    function mint(address to, address pol, uint256 str, uint256 amt, uint256 bor, bytes calldata dat) external;
    function edit(uint256 id, int256 amt, int256 bor, bytes calldata dat) external;
    function burn(uint256 id) external;
    function approve(address spender, uint256 id) external;
    function safeTransferFrom(address from, address to, uint256 id) external;
    function balanceOf(address owner) external view returns (uint256);
    function ownerOf(uint256 id) external view returns (address);
    function investor() external view returns (address);
}

