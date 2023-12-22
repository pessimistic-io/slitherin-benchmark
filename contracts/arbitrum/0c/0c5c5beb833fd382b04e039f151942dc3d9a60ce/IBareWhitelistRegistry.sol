// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.7.6;

/**
 * Used only as a 0.7.6 WhitelistManager for the UniLiquidityManager.
 */
interface IBareWhitelistRegistry {
    /**
     * @dev function meant to be called by contracts (usually in initializer) to register a whitelist manager for that contract
     * @param manager the address of the vault's whitelist manager
     * No access control, since any given contract can only modify their own data here.
     */
    function registerWhitelistManager(address manager) external;

    function permissions(address, address) external view returns (uint256);
}

