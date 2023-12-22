// SPDX-License-Identifier: MIT



pragma solidity >=0.8.0;

interface IGmxAdapter {
    /// @notice Swaps tokens along the route determined by the path
    /// @dev The input token is Vault's underlying
    /// @param path An array of token address to swap through
    /// @param amountIn The amount of input tokens
    /// @param minOut The minimum amount of output tokens that must be received
    /// @return boughtAmount Amount of the bought tokens
    function buy(
        address[] memory path,
        uint256 amountIn,
        uint256 minOut
    ) external returns (uint256 boughtAmount);

    /// @notice Sells back part of  bought tokens along the route
    /// @dev The output token is Vault's underlying
    /// @param path An array of token address to swap through
    /// @param amountIn The amount of input tokens
    /// @param minOut The minimum amount of output tokens (vault't underlying) that must be received
    /// @return amount of the bought tokens
    function sell(
        address[] memory path,
        uint256 amountIn,
        uint256 minOut
    ) external returns (uint256 amount);

    /// @notice Sells all specified tokens for Vault's underlying
    /// @dev Can be executed only by trader
    /// @param path An array of token address to swap through
    /// @param minOut The minimum amount of output tokens that must be received
    function close(
        address[] memory path,
        uint256 minOut
    ) external returns (uint256);

    /// @notice Sells all specified tokens for Vault's underlying
    /// @dev Can be executed by anyone with delay
    /// @param path An array of token address to swap through
    /// @param minOut The minimum amount of output tokens that must be received
    function forceClose(
        address[] memory path,
        uint256 minOut
    ) external returns (uint256);

    /// @notice Creates leverage long or short position order at GMX
    /// @dev Calls createIncreasePosition() in GMXPositionRouter
    function leveragePosition() external returns (uint256);

    /// @notice Create order for closing/decreasing position at GMX
    /// @dev Calls createDecreasePosition() in GMXPositionRouter
    function closePosition() external returns (uint256);

    /// @notice Create order for closing position at GMX
    /// @dev Calls createDecreasePosition() in GMXPositionRouter
    ///      Can be executed by any user
    /// @param positionId Position index for vault
    function forceClosePosition(uint256 positionId) external returns (uint256);

    /// @notice Returns data for open position
    // todo
    function getPosition(uint256) external view returns (uint256[] memory);

    struct AdapterOperation {
        uint8 operationId;
        bytes data;
    }

    /// @notice Checks if operations are allowed on adapter
    /// @param traderOperations Array of suggested trader operations
    /// @return Returns 'true' if operation is allowed on adapter
    function isOperationAllowed(
        AdapterOperation[] memory traderOperations
    ) external view returns (bool);

    /// @notice Executes array of trader operations
    /// @param traderOperations Array of trader operations
    /// @return Returns 'true' if all trades completed with success
    function executeOperation(
        AdapterOperation[] memory traderOperations
    ) external returns (bool);
}

