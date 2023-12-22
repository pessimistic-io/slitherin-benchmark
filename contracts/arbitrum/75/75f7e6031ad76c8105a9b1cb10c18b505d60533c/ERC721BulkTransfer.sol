
// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.2;
import "./IERC721Enumerable.sol";
import "./IERC721.sol";
import "./Ownable.sol";
import "./Context.sol";

contract ERC721BulkTransfer is Context {

    mapping(address => bool) private adminAccess;

    constructor() {
    }
    function bulkTransferERC721(uint256[] memory tokenIds, address[] memory receivers, address tokenAddress) external {
        IERC721 token = IERC721(tokenAddress);
        for(uint256 i = 0; i < tokenIds.length; i++) {
            token.transferFrom(_msgSender() , receivers[i], tokenIds[i]);
        }
    }
    function transferWithAmount(address receiver, uint256 amount, address tokenAddress) external {
        IERC721Enumerable token = IERC721Enumerable(tokenAddress);
        uint256 balance = token.balanceOf(_msgSender());
        require(amount <= balance, "Not enough balance");
        for(uint256 i = 0; i < amount; i++) {
            token.transferFrom(_msgSender() , receiver, token.tokenOfOwnerByIndex(_msgSender(), 0));
        }
    }
    function bulkTransferWithAmount(address[] memory receivers, uint256[] memory amounts, address tokenAddress) external {
        IERC721Enumerable token = IERC721Enumerable(tokenAddress);
        require(receivers.length == amounts.length, "Wrong input");
        for(uint256 i = 0; i < receivers.length; i++) {
            for(uint256 j = 0; j < amounts[i]; j++) {
                token.transferFrom(_msgSender() , receivers[i], token.tokenOfOwnerByIndex(_msgSender(), 0));
            }
        }
    }
}
