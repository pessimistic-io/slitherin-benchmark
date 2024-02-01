// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

error ZeroAddressNotAllowed();

/// @title IResolver
/// @author Chain Labs
/// @notice Interface of Resolver contract
interface IResolver {
    function calculateFee(uint256 _schmintExecuted, address _owner)
        external
        view
        returns (uint256 _fee, address _feeReceiver);

    function isActive() external view returns (bool);

    function ops() external view returns (address);

    function setupInputResolver()
        external
        view
        returns (
            address,
            address,
            address,
            address
        );
}

