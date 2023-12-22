// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity >=0.8.0 <0.9.0;

/// @notice As per https://github.com/Uniswap/swap-router-contracts/blob/main/contracts/interfaces/IMulticallExtended.sol
interface IAMulticall {
    /// @notice Enables calling multiple methods in a single call to the contract
    /// @param data Array of encoded calls.
    /// @return results Array of call responses.
    function multicall(bytes[] calldata data) external returns (bytes[] memory results);

    /// @notice Call multiple functions in the current contract and return the data from all of them if they all succeed
    /// @dev The `msg.value` should not be trusted for any method callable from multicall.
    /// @param deadline The time by which this function must be called before failing
    /// @param data The encoded function data for each of the calls to make to this contract
    /// @return results The results from each of the calls passed in via data
    function multicall(uint256 deadline, bytes[] calldata data) external payable returns (bytes[] memory results);

    /// @notice Call multiple functions in the current contract and return the data from all of them if they all succeed
    /// @dev The `msg.value` should not be trusted for any method callable from multicall.
    /// @param previousBlockhash The expected parent blockHash
    /// @param data The encoded function data for each of the calls to make to this contract
    /// @return results The results from each of the calls passed in via data
    function multicall(bytes32 previousBlockhash, bytes[] calldata data)
        external
        payable
        returns (bytes[] memory results);
}

