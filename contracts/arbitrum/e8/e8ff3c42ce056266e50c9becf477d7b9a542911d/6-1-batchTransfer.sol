// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./IERC721.sol";

contract BatchTransfer {
    struct NativeTx {
        address recipient;
        uint256 value; // wei
    }

    struct Erc20Tx {
        address recipient;
        address token;
        uint256 amount; // unit
    }

    struct Erc721Tx {
        address recipient;
        address token;
        uint256 tokenId;
    }

    function batchTransferEther(NativeTx[] calldata txs) public payable virtual {
        for (uint256 i = 0; i < txs.length; ++i) {
            payable(txs[i].recipient).transfer(txs[i].value);
        }

        if (address(this).balance > 0) {
            payable(msg.sender).transfer(address(this).balance);
        }
    }

    function batchTransferErc20(Erc20Tx[] calldata txs) public virtual {
        for (uint256 i = 0; i < txs.length; ++i) {
            (address recipient, address token, uint256 amount) = (txs[i].recipient, txs[i].token, txs[i].amount);
            IERC20(token).transferFrom(msg.sender, recipient, amount);
        }
    }

    function batchTransferErc721(Erc721Tx[] calldata txs) public virtual {
        for (uint256 i = 0; i < txs.length; ++i) {
            (address recipient, address token, uint256 tokenId) = (txs[i].recipient, txs[i].token, txs[i].tokenId);
            IERC721(token).transferFrom(msg.sender, recipient, tokenId);
        }
    }
}

