// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
pragma solidity 0.8.17;

import "./IERC165.sol";
import "./IERC721Receiver.sol";
import "./IERC1155Receiver.sol";
import "./IERC1271.sol";
import "./IIdentity.sol";
import "./ECDSA.sol";

contract DelegateModule is
    IERC165,
    IERC721Receiver,
    IERC1155Receiver,
    IERC1271
{
    using ECDSA for bytes32;

    function supportsInterface(bytes4 interfaceID)
        external
        pure
        override
        returns (bool)
    {
        return
            interfaceID == type(IERC165).interfaceId ||
            interfaceID == type(IERC721Receiver).interfaceId ||
            interfaceID == type(IERC1155Receiver).interfaceId ||
            interfaceID == type(IERC1271).interfaceId;
    }

    function onERC721Received(
        address, /* operator */
        address, /* from */
        uint256, /* tokenID */
        bytes calldata /* data */
    ) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    function onERC1155Received(
        address, /* operator */
        address, /* from */
        uint256, /* id */
        uint256, /* value */
        bytes calldata /* data */
    ) external pure override returns (bytes4) {
        return IERC1155Receiver.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address, /* operator */
        address, /* from */
        uint256[] calldata, /* ids */
        uint256[] calldata, /* values */
        bytes calldata /* data */
    ) external pure override returns (bytes4) {
        return IERC1155Receiver.onERC1155BatchReceived.selector;
    }

    function isValidSignature(bytes32 hash, bytes memory signature)
        external
        view
        override
        returns (bytes4)
    {
        require(signature.length == 65, "DM: invalid signature length");

        address signer = hash.recover(signature);

        require(signer == IIdentity(msg.sender).owner(), "DM: invalid signer");

        return IERC1271.isValidSignature.selector;
    }
}

