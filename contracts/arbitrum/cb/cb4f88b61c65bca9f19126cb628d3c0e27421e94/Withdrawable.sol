// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./Ownable.sol";
import "./IERC20.sol";
import "./IERC1155.sol";
import "./IERC721.sol";

contract Withdrawable is Ownable {

    function withdrawERC20(IERC20 erc20Token) external onlyOwner {
        erc20Token.transfer(msg.sender, erc20Token.balanceOf(address(this)));
    }

    function withdrawERC721(IERC721 erc721Token, uint256 id) external onlyOwner {
        erc721Token.safeTransferFrom(address(this), msg.sender, id);
    }

    function withdrawERC1155(
        address erc1155Token,
        uint256 id,
        uint256 amount
    ) public onlyOwner {
        IERC1155(erc1155Token).safeTransferFrom(
            address(this),
            msg.sender,
            id,
            amount,
            ""
        );
    }

    function withdrawEarnings(address to, uint256 balance) external onlyOwner {
        payable(to).transfer(balance);
    }

}
