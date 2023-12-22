// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IPremiaPool.sol";

import "./IVaultAdmin.sol";
import "./IVaultBase.sol";
import "./IVaultEvents.sol";
import "./IVaultView.sol";

/**
 * @title Knox Vault Interface
 */

interface IVault is IVaultAdmin, IVaultBase, IVaultEvents, IVaultView {
    /**
     * @notice gets the collateral asset ERC20 interface
     * @return ERC20 interface
     */
    function ERC20() external view returns (IERC20);

    /**
     * @notice gets the pool interface
     * @return pool interface
     */
    function Pool() external view returns (IPremiaPool);
}

