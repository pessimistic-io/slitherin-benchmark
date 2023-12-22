//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import {ERC1155} from "./ERC1155.sol";
import {Auth, Authority} from "./Auth.sol";
import {ERC2981} from "./ERC2981.sol";

/**
 * @title Blueberry Lab Items
 * @author IrvingDevPro
 * @notice This contract manage the tokens usable by GBC holders
 */
contract GBCLab is ERC1155, Auth, ERC2981 {
    constructor(address _owner, Authority _authority)
        Auth(_owner, _authority)
    {}

    string private _uri;
    mapping(uint256 => string) private _uris;

    function uri(uint256 id) public view override returns (string memory) {
        string memory uri_ = _uris[id];
        if (bytes(uri_).length > 0) return uri_;
        return _uri;
    }

    function setUri(string memory uri_) external requiresAuth {
        _uri = uri_;
    }

    function setUri(uint256 id, string memory uri_) external requiresAuth {
        _uris[id] = uri_;
        if (bytes(uri_).length == 0) {
            emit URI(_uri, id);
        } else {
            emit URI(uri_, id);
        }
    }

    function mint(
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) external requiresAuth {
        _mint(to, id, amount, data);
    }

    function batchMint(
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) external requiresAuth {
        _batchMint(to, ids, amounts, data);
    }

    function burn(
        address to,
        uint256 id,
        uint256 amount
    ) external requiresAuth {
        _burn(to, id, amount);
    }

    function batchBurn(
        address to,
        uint256[] memory ids,
        uint256[] memory amounts
    ) external requiresAuth {
        _batchBurn(to, ids, amounts);
    }

    function setRoyalty(
        uint256 id,
        address receiver,
        uint96 feeNumerator
    ) external requiresAuth {
        if (receiver == address(0)) return _resetTokenRoyalty(id);
        _setTokenRoyalty(id, receiver, feeNumerator);
    }

    function setRoyalty(address receiver, uint96 feeNumerator)
        external
        requiresAuth
    {
        if (receiver == address(0)) return _deleteDefaultRoyalty();
        _setDefaultRoyalty(receiver, feeNumerator);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        pure
        override(ERC1155, ERC2981)
        returns (bool)
    {
        return
            interfaceId == 0x2a55205a || // ERC165 Interface ID for ERC2981
            interfaceId == 0x01ffc9a7 || // ERC165 Interface ID for ERC165
            interfaceId == 0xd9b67a26 || // ERC165 Interface ID for ERC1155
            interfaceId == 0x0e89341c; // ERC165 Interface ID for ERC1155MetadataURI
    }
}

