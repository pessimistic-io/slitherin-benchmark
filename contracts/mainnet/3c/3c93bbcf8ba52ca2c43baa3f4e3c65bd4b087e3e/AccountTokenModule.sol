//SPDX-License-Identifier: MIT
pragma solidity >=0.8.11 <0.9.0;

import "./NftModule.sol";
import "./IAccountTokenModule.sol";
import "./IAccountModule.sol";

import "./SafeCast.sol";

/**
 * @title Module with custom NFT logic for the account token.
 * @dev See IAccountTokenModule.
 */
contract AccountTokenModule is IAccountTokenModule, NftModule {
    using SafeCastU256 for uint256;

    /**
     * @dev Updates account RBAC storage to track the current owner of the token.
     */
    function _postTransfer(
        address, // from (unused)
        address to,
        uint256 tokenId
    ) internal virtual override {
        IAccountModule(OwnableStorage.getOwner()).notifyAccountTransfer(to, tokenId.to128());
    }
}

