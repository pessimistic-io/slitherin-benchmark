// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.9;

import "./IPool.sol";
import "./IAaveV3Vault.sol";
import "./IVaultGovernance.sol";

interface IAaveV3VaultGovernance is IVaultGovernance {
    /// @notice Params that could be changed by Protocol Governance with Protocol Governance delay.
    /// @param pool Reference to Aave Pool
    /// @param estimatedAaveAPY APY estimation for calulating tvl range. Measured in CommonLibrary.DENOMINATOR
    struct DelayedProtocolParams {
        IPool pool;
        uint256 estimatedAaveAPY;
    }

    /// @notice Delayed Protocol Params, i.e. Params that could be changed by Protocol Governance with Protocol Governance delay.
    function delayedProtocolParams() external view returns (DelayedProtocolParams memory);

    /// @notice Delayed Protocol Params staged for commit after delay.
    function stagedDelayedProtocolParams() external view returns (DelayedProtocolParams memory);

    /// @notice Stage Delayed Protocol Params, i.e. Params that could be changed by Protocol Governance with Protocol Governance delay.
    /// @dev Can only be called after delayedProtocolParamsTimestamp.
    /// @param params New params
    function stageDelayedProtocolParams(DelayedProtocolParams calldata params) external;

    /// @notice Commit Delayed Protocol Params, i.e. Params that could be changed by Protocol Governance with Protocol Governance delay.
    function commitDelayedProtocolParams() external;

    /// @notice Deploys a new vault.
    /// @param vaultTokens_ ERC20 tokens that will be managed by this Vault
    /// @param owner_ Owner of the vault NFT
    function createVault(address[] memory vaultTokens_, address owner_)
        external
        returns (IAaveV3Vault vault, uint256 nft);
}

