// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./ILBPair.sol";

interface ISPVFactory {
    event VaultImplementationSet(address vaultImplementation);

    event DefaultManagerSet(address defaultManager);

    event SPVaultCreated(address vault, ILBPair pair, uint256 id);

    function getDefaultManager() external view returns (address);

    function getVaultImplementation() external view returns (address);

    function getVaults(ILBPair pair) external view returns (address[] memory);

    function getVaultAt(uint256 id) external view returns (address);

    function setVaultImplementation(address vaultImplementation) external;

    function setDefaultManager(address manager) external;

    function createSPVault(ILBPair pair) external returns (address);
}

