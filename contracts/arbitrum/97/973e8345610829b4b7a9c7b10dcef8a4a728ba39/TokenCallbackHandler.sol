// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.17;

/* solhint-disable no-empty-blocks */

import "./IERC165.sol";
import "./IERC777Recipient.sol";
import "./IERC721Receiver.sol";
import "./IERC1155Receiver.sol";

/**
 * @title TokenCallbackHandler
 * @author fun.xyz
 * @notice Token callback handler.
 * Handles supported tokens' callbacks, allowing account receiving these tokens.
 */
contract TokenCallbackHandler is IERC777Recipient, IERC721Receiver, IERC1155Receiver {
	/**
	 * @dev This hook is used for ERC-777 tokens
	 */
	function tokensReceived(address, address, address, uint256, bytes calldata, bytes calldata) external pure override {}

	/**
	 * @dev Whenever an {IERC721} `tokenId` token is transferred to this contract via {IERC721-safeTransferFrom}
	 * by `operator` from `from`, this function is called.
	 *
	 * It must return its Solidity selector to confirm the token transfer.
	 * If any other value is returned or the interface is not implemented by the recipient, the transfer will be reverted.
	 *
	 * The selector can be obtained in Solidity with `IERC721Receiver.onERC721Received.selector`.
	 *
	 * @return `bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"))` if transfer is allowed
	 */
	function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
		return IERC721Receiver.onERC721Received.selector;
	}

	/**
	 * @dev Handles the receipt of a single ERC1155 token type. This function is
	 * called at the end of a `safeTransferFrom` after the balance has been updated.
	 *
	 * NOTE: To accept the transfer, this must return
	 * `bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)"))`
	 * (i.e. 0xf23a6e61, or its own function selector).
	 *
	 * @return `bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)"))` if transfer is allowed
	 */
	function onERC1155Received(address, address, uint256, uint256, bytes calldata) external pure override returns (bytes4) {
		return IERC1155Receiver.onERC1155Received.selector;
	}

	/**
	 * @dev Handles the receipt of a multiple ERC1155 token types. This function
	 * is called at the end of a `safeBatchTransferFrom` after the balances have
	 * been updated.
	 *
	 * NOTE: To accept the transfer(s), this must return
	 * `bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"))`
	 * (i.e. 0xbc197c81, or its own function selector).
	 *
	 * @return `bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"))` if transfer is allowed
	 */
	function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata) external pure override returns (bytes4) {
		return IERC1155Receiver.onERC1155BatchReceived.selector;
	}

	/**
	 * @dev Returns true if this contract implements the interface defined by
	 * `interfaceId`. See the corresponding
	 * https://eips.ethereum.org/EIPS/eip-165#how-interfaces-are-identified[EIP section]
	 * to learn more about how these ids are created.
	 *
	 * This function call must use less than 30 000 gas.
	 *
	 * @return true if interfaceId is supported(IERC721Receiver, IERC1155Receiver, IERC165), false otherwise
	 */
	function supportsInterface(bytes4 interfaceId) external view virtual override returns (bool) {
		return
			interfaceId == type(IERC721Receiver).interfaceId ||
			interfaceId == type(IERC1155Receiver).interfaceId ||
			interfaceId == type(IERC165).interfaceId;
	}
}

