//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC1155BurnableUpgradeable.sol";
import "./IERC1155Upgradeable.sol";
import "./IERC1155MetadataURIUpgradeable.sol";
import "./Initializable.sol";
import "./IAccessControlEnumerableUpgradeable.sol";

import "./UtilitiesV2Upgradeable.sol";

abstract contract SmolRacingTrophiesState is Initializable, UtilitiesV2Upgradeable, ERC1155BurnableUpgradeable {
    event BaseUriChanged(string indexed _newUri);
    
    string public baseURI;

    function __SmolRacingTrophiesState_init() internal initializer {
        UtilitiesV2Upgradeable.__Utilities_init();
        ERC1155BurnableUpgradeable.__ERC1155Burnable_init();
        ERC1155Upgradeable.__ERC1155_init_unchained("");
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(AccessControlEnumerableUpgradeable, ERC1155Upgradeable) returns (bool) {
        return interfaceId == type(IAccessControlEnumerableUpgradeable).interfaceId
            || interfaceId == type(IERC1155Upgradeable).interfaceId
            || interfaceId == type(IERC1155MetadataURIUpgradeable).interfaceId
            || super.supportsInterface(interfaceId);
    }
}
