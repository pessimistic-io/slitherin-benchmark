// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

struct MultiChainData {
    address router;
}

struct AnyMapping {
    address tokenAddress;
    address anyTokenAddress;
}

interface IMultichainBridge {
    function Swapout(uint256 amount, address bindaddr) external returns (bool);

    function anySwapOutUnderlying(address token, address to, uint256 amount, uint256 toChainID) external;

    function anySwapOut(address token, address to, uint256 amount, uint256 toChainID) external;

    function anySwapOutNative(address token, address to, uint256 toChainID) external payable;

    function wNATIVE() external returns (address);

    function transfers(bytes32 transferId) external view returns (bool);
}

