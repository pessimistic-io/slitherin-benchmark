// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

import {IONFT1155Upgradeable} from "./IONFT1155Upgradeable.sol";
import {Initializable, IERC165Upgradeable, ONFT1155CoreUpgradeable, AccessControlUpgradeable} from "./ONFT1155CoreUpgradeable.sol";
import {ERC1155SupplyUpgradeable, ERC1155Upgradeable} from "./ERC1155SupplyUpgradeable.sol";

// NOTE: this ONFT contract has no public minting logic.
// must implement your own minting logic in child classes
contract ONFT1155Upgradeable is
    Initializable,
    ONFT1155CoreUpgradeable,
    ERC1155SupplyUpgradeable,
    IONFT1155Upgradeable
{
    function __ONFT1155Upgradeable_init(
        string memory _uri,
        address _lzEndpoint
    ) internal onlyInitializing {
        __ERC1155_init_unchained(_uri);
        __AccessControl_init_unchained();
        __LzAppUpgradeable_init_unchained(_lzEndpoint);
    }

    function __ONFT1155Upgradeable_init_unchained() internal onlyInitializing {}

    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        virtual
        override(
            ONFT1155CoreUpgradeable,
            ERC1155Upgradeable,
            IERC165Upgradeable
        )
        returns (bool)
    {
        return
            interfaceId == type(IONFT1155Upgradeable).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    function _debitFrom(
        address _from,
        uint16,
        bytes memory,
        uint[] memory _tokenIds,
        uint[] memory _amounts
    ) internal virtual override {
        address spender = _msgSender();
        require(spender == _from || isApprovedForAll(_from, spender), "!df");
        _burnBatch(_from, _tokenIds, _amounts);
    }

    function _creditTo(
        uint16,
        address _toAddress,
        uint[] memory _tokenIds,
        uint[] memory _amounts
    ) internal virtual override {
        _mintBatch(_toAddress, _tokenIds, _amounts, "");
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint[50] private __gap;
}

