// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {IERC1271} from "./IERC1271.sol";
import {ERC1155} from "./ERC1155.sol";
import {Address} from "./Address.sol";
import {IERC165} from "./IERC165.sol";
import {ECDSA} from "./ECDSA.sol";
import {EIP712} from "./EIP712.sol";

import {IERC1155Permit} from "./IERC1155Permit.sol";

contract ERC1155Permit is ERC1155, IERC1155Permit, EIP712 {
    mapping(address => uint256) public override nonces;

    bytes32 public constant override PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address operator,bool approved,uint256 nonce,uint256 deadline)");

    constructor(string memory uri_, string memory name, string memory version) ERC1155(uri_) EIP712(name, version) {}

    function permit(address owner, address operator, bool approved, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external
        override
    {
        if (block.timestamp > deadline) revert PermitExpired();

        bytes32 digest = _hashTypedDataV4(
            keccak256(abi.encode(PERMIT_TYPEHASH, owner, operator, approved, nonces[owner]++, deadline))
        );

        if (Address.isContract(owner)) {
            if (IERC1271(owner).isValidSignature(digest, abi.encodePacked(r, s, v)) != 0x1626ba7e) {
                revert InvalidSignature();
            }
        } else {
            if (ECDSA.recover(digest, v, r, s) != owner) revert InvalidSignature();
        }

        _setApprovalForAll(owner, operator, approved);
    }

    function DOMAIN_SEPARATOR() external view override returns (bytes32) {
        return _domainSeparatorV4();
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC1155, IERC165) returns (bool) {
        return interfaceId == type(IERC1155Permit).interfaceId || super.supportsInterface(interfaceId);
    }
}

