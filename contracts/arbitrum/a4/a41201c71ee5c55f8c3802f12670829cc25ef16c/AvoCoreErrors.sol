// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

abstract contract AvoCoreErrors {
    /// @notice thrown when a signature has expired or when a request isn't valid yet
    error AvoCore__InvalidTiming();

    /// @notice thrown when someone is trying to execute a in some way auth protected logic
    error AvoCore__Unauthorized();

    /// @notice thrown when actions execution runs out of gas
    error AvoCore__OutOfGas();

    /// @notice thrown when a method is called with invalid params (e.g. a zero address as input param)
    error AvoCore__InvalidParams();

    /// @notice thrown when an EIP1271 signature is invalid
    error AvoCore__InvalidEIP1271Signature();

    /// @notice thrown when a `castAuthorized()` `fee` is bigger than the `maxFee` given through the input param
    error AvoCore__MaxFee(uint256 fee, uint256 maxFee);

    /// @notice thrown when `castAuthorized()` fee can not be covered by available contract funds
    error AvoCore__InsufficientBalance(uint256 fee);
}

