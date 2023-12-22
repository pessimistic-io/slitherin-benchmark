// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.9;

import "./Initializable.sol";
import "./Ownable.sol";
import "./IERC721.sol";
import "./SafeMath.sol";
import "./ERC165Storage.sol";

import "./ERC721A.sol";

import {IERC721AutoIdMinterExtension} from "./ERC721AutoIdMinterExtension.sol";

/**
 * @dev Extension to add minting capability with an auto incremented ID for each token and a maximum supply setting.
 */
abstract contract ERC721AMinterExtension is
    Initializable,
    Ownable,
    ERC165Storage,
    ERC721A
{
    using SafeMath for uint256;

    uint256 public maxSupply;
    bool public maxSupplyFrozen;

    function __ERC721AMinterExtension_init(uint256 _maxSupply)
        internal
        onlyInitializing
    {
        __ERC721AMinterExtension_init_unchained(_maxSupply);
    }

    function __ERC721AMinterExtension_init_unchained(uint256 _maxSupply)
        internal
        onlyInitializing
    {
        maxSupply = _maxSupply;

        _registerInterface(type(IERC721AutoIdMinterExtension).interfaceId);
        _registerInterface(type(IERC721).interfaceId);
        _registerInterface(type(IERC721A).interfaceId);
    }

    /* ADMIN */

    function setMaxSupply(uint256 newValue) external onlyOwner {
        require(!maxSupplyFrozen, "BASE_URI_FROZEN");
        maxSupply = newValue;
    }

    function freezeMaxSupply() external onlyOwner {
        maxSupplyFrozen = true;
    }

    /* PUBLIC */

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC165Storage, ERC721A)
        returns (bool)
    {
        return ERC165Storage.supportsInterface(interfaceId);
    }

    /* INTERNAL */

    function _mintTo(address to, uint256 count) internal {
        require(totalSupply() + count <= maxSupply, "EXCEEDS_MAX_SUPPLY");
        _safeMint(to, count);
    }
}

