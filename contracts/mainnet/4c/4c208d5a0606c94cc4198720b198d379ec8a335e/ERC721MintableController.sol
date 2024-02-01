// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { IERC721MintableController } from "./IERC721MintableController.sol";
import { ERC721MintableModel } from "./ERC721MintableModel.sol";
import { ERC721SupplyController } from "./ERC721SupplyController.sol";
import { ERC721TokenUtils } from "./ERC721TokenUtils.sol";
import { AddressUtils } from "./AddressUtils.sol";
import { IntegerUtils } from "./IntegerUtils.sol";

abstract contract ERC721MintableController is
    IERC721MintableController,
    ERC721MintableModel,
    ERC721SupplyController
{
    using ERC721TokenUtils for address;
    using AddressUtils for address;
    using IntegerUtils for uint256;

    function mintBalanceOf_(address owner) internal view virtual returns (uint256) {
        owner.enforceIsNotZeroAddress();
        return _mintBalanceOf(owner);
    }

    function mint_(uint256 amount) internal virtual {
        _enforceCanMint(amount);
        (uint256 tokenId, uint256 maxTokenId) = _mint_(msg.sender, amount);

        unchecked {
            while (tokenId < maxTokenId) {
                emit Transfer(address(0), msg.sender, tokenId++);
            }
        }
    }

    function _mint_(address to, uint256 amount)
        internal
        virtual
        returns (uint256 tokenId, uint256 maxTokenId)
    {
        tokenId = to.toTokenId() | _mintBalanceOf(to);
        maxTokenId = tokenId + amount;
        _mint(to, amount);
        _updateAvailableSupply(amount);
    }

    function _mintValue() internal view virtual returns (uint256) {
        return 0 ether;
    }

    function _mintedSupply() internal view virtual returns (uint256) {
        return _initialSupply() - _availableSupply();
    }

    function _enforceCanMint(uint256 amount) internal view virtual {
        amount.enforceIsNotZero();
        amount.enforceNotGreaterThan(_availableSupply());
        msg.value.enforceEquals(amount * _mintValue());
        (_mintBalanceOf(msg.sender) + amount).enforceNotGreaterThan(_maxMintBalance());
    }
}

