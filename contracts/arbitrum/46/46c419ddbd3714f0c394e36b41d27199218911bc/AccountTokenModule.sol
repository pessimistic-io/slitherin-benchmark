/*
Licensed under the Voltz v2 License (the "License"); you 
may not use this file except in compliance with the License.
You may obtain a copy of the License at

https://github.com/Voltz-Protocol/v2-core/blob/main/core/LICENSE
*/
pragma solidity >=0.8.19;

import "./IAccountTokenModule.sol";
import "./IAccountModule.sol";
import "./SafeCast.sol";
import "./NftModule.sol";

/**
 * @title Account Token
 * @dev See IAccountTokenModule
 */
contract AccountTokenModule is IAccountTokenModule, NFT {
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

        //todo: reset permissions
    }
}

