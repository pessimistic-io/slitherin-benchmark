//SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

/// @title The interface for the Unipilot Factory
interface IUnipilotFactory {
    /// @notice Emitted when a vault is created
    /// @param _tokenA The first token of the pool by address sort order
    /// @param _tokenB The second token of the pool by address sort order
    /// @param _vault The address of the vault that is created
    event VaultCreated(
        address indexed _tokenA,
        address indexed _tokenB,
        uint16 _strategyType,
        address indexed _vault
    );

    /// @notice Emitted when the governance of the factory is changed
    /// @param _oldGovernance The governance before the governance was changed
    /// @param _newGovernance The governance after the governance was changed
    event GovernanceChanged(
        address indexed _oldGovernance,
        address indexed _newGovernance
    );

    /// @notice Creates a vault for the given two tokens and fee
    /// @param _tokenA The first token of the pool by address sort order
    /// @param _tokenB The second token of the pool by address sort order
    /// @dev tokenA and tokenB may be passed in either order: token0/token1 or token1/token0.
    /// The call will revert if the vault already exists, the fee is invalid, or the token arguments
    /// are invalid.
    /// @return _vault The address of the newly created pool
    function createVault(
        address _tokenA,
        address _tokenB,
        uint16 _vaultStrategy,
        uint160 _sqrtPriceX96,
        string memory _name,
        string memory _symbol
    ) external returns (address _vault);

    /// @notice Used to give addresses of governance, strategy, indexFund
    /// @return governance address, strategy address, indexFund address
    function getUnipilotDetails()
        external
        view
        returns (
            address,
            address,
            address,
            uint8,
            uint8
        );
}

