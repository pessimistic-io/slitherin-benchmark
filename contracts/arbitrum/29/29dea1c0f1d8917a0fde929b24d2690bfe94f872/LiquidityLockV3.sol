// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.9.0;

import "./Ownable.sol";

interface IERC721 {
    function isApprovedForAll(
        address owner,
        address operator
    ) external view returns (bool);

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external;
}

interface IERC721Receiver {
    /**
     * @dev Whenever an {IERC721} `tokenId` token is transferred to this contract via {IERC721-safeTransferFrom}
     * by `operator` from `from`, this function is called.
     *
     * It must return its Solidity selector to confirm the token transfer.
     * If any other value is returned or the interface is not implemented by the recipient, the transfer will be reverted.
     *
     * The selector can be obtained in Solidity with `IERC721Receiver.onERC721Received.selector`.
     */
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4);
}

pragma solidity ^0.8.0;

contract LiquidityLockV3 is Ownable, IERC721Receiver {
    uint256 public lockUntil;

    function initialize() public initializer {
        Ownable.__Ownable_init();
        lockUntil = block.timestamp + 200 days;
    }

    function withdrawToken(
        IERC721 _token,
        address _to,
        uint256 _tokenId
    ) external onlyOwner {
        require(block.timestamp > lockUntil, "Fail to withdraw!");
        _token.safeTransferFrom(address(this), _to, _tokenId);
    }

    function lockToken(IERC721 _token, uint256 _tokenId) external onlyOwner {
        _token.safeTransferFrom(msg.sender, address(this), _tokenId);
    }

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) public pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}

