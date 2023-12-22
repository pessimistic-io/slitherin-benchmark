// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IERC1155.sol";
import "./IERC721.sol";

import "./IHuntBridge.sol";
import "./IGlobalNftDeployer.sol";

library GlobalNftLib {
    function transfer(
        IHuntBridge bridge,
        uint64 originChain,
        bool isErc1155,
        address addr,
        uint256 tokenId,
        address recipient,
        bool withdraw
    ) internal {
        address nft = originChain == block.chainid ? addr : bridge.calcAddr(originChain, addr);
        if (originChain == block.chainid || !withdraw) {
            /// native chain or dont want to withdraw
            if (isErc1155) {
                IERC1155(nft).safeTransferFrom(address(this), recipient, tokenId, 1, "");
            } else {
                IERC721(nft).transferFrom(address(this), recipient, tokenId);
            }
        } else {
            if (isErc1155) {
                IERC1155(nft).setApprovalForAll(address(bridge), true);
            } else {
                IERC721(nft).approve(address(bridge), tokenId);
            }
            bridge.withdraw{ value: msg.value }(originChain, addr, tokenId, recipient, payable(msg.sender));
        }
    }

    function isOwned(
        IHuntBridge bridge,
        uint64 originChain,
        bool isErc1155,
        address addr,
        uint256 tokenId
    ) internal view returns (bool) {
        address nft = originChain == block.chainid ? addr : bridge.calcAddr(originChain, addr);
        if (isErc1155) {
            return IERC1155(nft).balanceOf(address(this), tokenId) == 1;
        } else {
            return IERC721(nft).ownerOf(tokenId) == address(this);
        }
    }
}

