// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC20Metadata.sol";
import "./ERC4626Base.sol";
import "./Multicall.sol";

import "./VaultInternal.sol";

/**
 * @title Knox Vault Base Contract
 * @dev deployed standalone and referenced by VaultDiamond
 */

contract VaultBase is ERC20Metadata, ERC4626Base, Multicall, VaultInternal {
    using SafeERC20 for IERC20;
    using VaultStorage for VaultStorage.Layout;

    constructor(bool isCall, address pool) VaultInternal(isCall, pool) {}

    /************************************************
     *  ERC4626 OVERRIDES
     ***********************************************/

    // this contract overrides the ERC4626 standard deposit, and mint functions such
    // that they are only callable by the queue contract. the vault assumes deposits
    // are made once per week. this was done to prevent users from entering vault in
    // the middle or end of an epoch, then leaving without taking any risk but
    // potentially making a profit.

    /**
     * @notice execute a deposit of assets on behalf of given address
     * @param assetAmount quantity of assets to deposit
     * @param receiver recipient of shares resulting from deposit
     * @return shareAmount quantity of shares to mint
     */
    function _deposit(uint256 assetAmount, address receiver)
        internal
        override(ERC4626BaseInternal)
        onlyQueue
        returns (uint256)
    {
        return super._deposit(assetAmount, receiver);
    }

    /**
     * @notice execute a minting of shares on behalf of given address
     * @param shareAmount quantity of shares to mint
     * @param receiver recipient of shares resulting from deposit
     * @return assetAmount quantity of assets to deposit
     */
    function _mint(uint256 shareAmount, address receiver)
        internal
        override(ERC4626BaseInternal)
        onlyQueue
        returns (uint256)
    {
        return super._mint(shareAmount, receiver);
    }

    // this contract overrides the ERC4626 standard withdraw, and redeem functions
    // such that they are only callable after the auction has been processed. during
    // the auction the vaults balance must remain constant, the auction contract
    // queries the vault for its available amount of collateral once in the beginning
    // of the auction. therefore it is required the vault's collateral amount does
    // not change until the vault has underwritten the options sold during the
    // auction.

    /**
     * @notice execute a withdrawal of assets on behalf of given address
     * @param assetAmount quantity of assets to withdraw
     * @param receiver recipient of assets resulting from withdrawal
     * @param owner holder of shares to be redeemed
     * @return shareAmount quantity of shares to redeem
     */
    function _withdraw(
        uint256 assetAmount,
        address receiver,
        address owner
    )
        internal
        override(ERC4626BaseInternal, VaultInternal)
        withdrawalsLocked
        returns (uint256)
    {
        return super._withdraw(assetAmount, receiver, owner);
    }

    /**
     * @notice execute a redemption of shares on behalf of given address
     * @param shareAmount quantity of shares to redeem
     * @param receiver recipient of assets resulting from withdrawal
     * @param owner holder of shares to be redeemed
     * @return assetAmount quantity of assets to withdraw
     */
    function _redeem(
        uint256 shareAmount,
        address receiver,
        address owner
    )
        internal
        override(ERC4626BaseInternal, VaultInternal)
        withdrawalsLocked
        returns (uint256)
    {
        return super._redeem(shareAmount, receiver, owner);
    }

    // this contract overrides the ERC4626 standard maxWithdraw, and maxRedeem functions
    // such that they account for unredeemed vault shares held by the queue when called.

    /**
     * @notice calculate the maximum quantity of base assets which may be withdrawn by given holder
     * @param owner holder of shares to be redeemed
     * @return maxAssets maximum asset mint amount
     */
    function _maxWithdraw(address owner)
        internal
        view
        override(ERC4626BaseInternal, VaultInternal)
        returns (uint256 maxAssets)
    {
        return super._maxWithdraw(owner);
    }

    /**
     * @notice calculate the maximum quantity of shares which may be redeemed by given holder
     * @param owner holder of shares to be redeemed
     * @return maxShares maximum share redeem amount
     */
    function _maxRedeem(address owner)
        internal
        view
        override(ERC4626BaseInternal, VaultInternal)
        returns (uint256 maxShares)
    {
        return super._maxRedeem(owner);
    }
}

