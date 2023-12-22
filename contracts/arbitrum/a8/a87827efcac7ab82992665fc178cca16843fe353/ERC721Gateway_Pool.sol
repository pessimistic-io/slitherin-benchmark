// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "./ERC721Gateway.sol";

interface IERC721 {
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external;
}

contract ERC721Gateway_Pool is ERC721Gateway {
    constructor(
        address anyCallProxy,
        uint256 flag,
        address token
    ) ERC721Gateway(anyCallProxy, flag, token) {}

    function description() external pure returns (string memory) {
        return "ERC721Gateway_Pool";
    }

    function _swapout(uint256 tokenId)
        internal
        virtual
        override
        returns (bool, bytes memory)
    {
        try
            IERC721(token).safeTransferFrom(msg.sender, address(this), tokenId)
        {
            return (true, "");
        } catch {
            return (false, "");
        }
    }

    function _swapin(
        uint256 tokenId,
        address receiver,
        bytes memory extraMsg
    ) internal override returns (bool) {
        try
            IERC721(token).safeTransferFrom(address(this), msg.sender, tokenId)
        {
            return true;
        } catch {
            return false;
        }
    }
}

