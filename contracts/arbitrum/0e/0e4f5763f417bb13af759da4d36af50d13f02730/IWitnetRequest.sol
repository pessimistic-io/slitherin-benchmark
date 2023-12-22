// SPDX-License-Identifier: MIT

pragma solidity >=0.7.0 <0.9.0;

/// @title The Witnet Data Request basic interface.
/// @author The Witnet Foundation.
interface IWitnetRequest {
    
    /// @notice A `IWitnetRequest` is constructed around a `bytes` value containing 
    /// @notice a well-formed Witnet Data Request using Protocol Buffers.
    function bytecode() external view returns (bytes memory);

    /// @notice Returns SHA256 hash of Witnet Data Request as CBOR-encoded bytes.
    function hash() external view returns (bytes32);
}

