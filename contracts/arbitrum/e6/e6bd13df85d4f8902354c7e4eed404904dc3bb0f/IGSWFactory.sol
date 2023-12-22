// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

interface IGSWFactory {
    function gswImpl() external view returns (address);

    /// @notice         Computes the deterministic address for owner based on Create2
    /// @param owner    GaslessSmartWallet owner
    /// @return         computed address for the contract
    function computeAddress(address owner) external view returns (address);

    /// @notice         Deploys if necessary or gets the address for a GaslessSmartWallet for a certain owner
    /// @param owner    GaslessSmartWallet owner
    /// @return         deployed address for the contract
    function deploy(address owner) external returns (address);
}

