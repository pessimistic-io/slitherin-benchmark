//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./ERC1155Upgradeable.sol";
import "./StringsUpgradeable.sol";

import "./UtilitiesUpgradeable.sol";

abstract contract ERC1155BaseUpgradeable is Initializable, ERC1155Upgradeable, UtilitiesUpgradeable {
    using StringsUpgradeable for uint256;

    string internal _uri;

    function __ERC1155BaseUpgradeable_init() internal onlyInitializing {
        ERC1155Upgradeable.__ERC1155_init("");
        __Utilities_init();
    }

    function setBaseUri(string calldata _newUri) external whenNotPaused requiresEitherRole(ADMIN_ROLE, OWNER_ROLE) {
        _uri = _newUri;
    }

    function getBaseUri() external view returns (string memory) {
        return _uri;
    }

    function uri(uint256 _typeId) public view virtual override returns (string memory) {
        return bytes(_uri).length > 0 ? string(abi.encodePacked(_uri, _typeId.toString())) : _uri;
    }

    function supportsInterface(bytes4 _interfaceId)
        public
        view
        override(UtilitiesUpgradeable, ERC1155Upgradeable)
        returns (bool)
    {
        return
            ERC1155Upgradeable.supportsInterface(_interfaceId) || UtilitiesUpgradeable.supportsInterface(_interfaceId);
    }
}

