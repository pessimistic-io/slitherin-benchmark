// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./Ownable.sol";
import "./IERC20.sol";
import "./IERC721.sol";
import "./IERC1155.sol";

contract Withdraw is Ownable {
    receive() external payable {}

    function withdrawBalance() public onlyOwner {
        require(address(this).balance > 0, "Balance must be larger than 0");
        payable(msg.sender).transfer(address(this).balance);
    }

    function withdrawToken(uint256 amount, IERC20 token) public onlyOwner {
        require(
            token.balanceOf(address(this)) >= amount,
            "Balance is reached limited"
        );
        token.transfer(owner(), amount);
    }

    function withdrawERC721Token(
        uint256 tokenId,
        IERC721 token
    ) public onlyOwner {
        require(
            token.ownerOf(tokenId) == address(this),
            "This token does not belong to Contract"
        );
        token.transferFrom(address(this), owner(), tokenId);
    }

    function withdrawERC1155Token(
        uint256[] memory ids,
        uint256[] memory amounts,
        IERC1155 token
    ) public onlyOwner {
        require(
            ids.length > 0 && ids.length == amounts.length,
            "Params is invalid"
        );
        for (uint256 i = 0; i < ids.length; i++) {
            require(
                token.balanceOf(address(this), ids[i]) >= amounts[i] &&
                    amounts[i] > 0,
                "This token does not belong to Contract"
            );
        }

        token.safeBatchTransferFrom(address(this), owner(), ids, amounts, "");
    }
}

