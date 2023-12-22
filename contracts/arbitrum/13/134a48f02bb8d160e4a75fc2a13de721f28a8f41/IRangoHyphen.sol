// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

/// @title An interface to RangoHyphen.sol contract to improve type hinting
/// @author Hellboy
interface IRangoHyphen {

    /// @notice Executes a bridging via hyphen
    /// @param _receiver The receiver address in the destination chain
    /// @param _token The requested token to bridge
    /// @param _amount The requested amount to bridge
    /// @param _dstChainId The network id of destination chain, ex: 56 for BSC
    function hyphenBridge(
        address _receiver,
        address _token,
        uint256 _amount,
        uint256 _dstChainId
    ) external;
}
