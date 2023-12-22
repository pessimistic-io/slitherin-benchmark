// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

/// @title Swap Aggregators Proxy contract
/// @author Matin Kaboli
/// @notice Swaps tokens using 3 protocols: paraswap, 1inch and 0x
/// @dev This contract uses Permit2
interface ISwapAggregators {
    /// @notice Swaps using 1Inch protocol
    /// @param _data 1Inch protocol data from API
    function swap1Inch(bytes calldata _data) external payable;

    /// @notice Swaps using 1Inch protocol
    /// @dev Uses ETH only
    /// @param _data 1Inch protocol generated data from API
    /// @param _proxyFee Fee of the proxy contract
    function swap1InchETH(bytes calldata _data, uint256 _proxyFee) external payable;

    /// @notice Swaps using Paraswap protocol
    /// @param _data Paraswap protocol generated data from API
    function swapParaswap(bytes calldata _data) external payable;

    /// @notice Swaps using Paraswap protocol
    /// @dev Uses ETH only
    /// @param _data Paraswap protocol generated data from API
    /// @param _proxyFee Fee of the proxy contract
    function swapParaswapETH(bytes calldata _data, uint256 _proxyFee) external payable;

    /// @notice Swaps using 0x protocol
    /// @param _swapTarget Swap target address, used for sending _data
    /// @param _data 0x protocol generated data from API
    function swap0x(address _swapTarget, bytes calldata _data) external payable;

    /// @notice Swaps using 0x protocol
    /// @param _swapTarget Swap target address, used for sending _data
    /// @param _proxyFee Fee of the proxy contract
    /// @param _data 0x protocol generated data from API
    function swap0xETH(address _swapTarget, bytes calldata _data, uint24 _proxyFee) external payable;
}

