// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8;

import {IERC20} from "./IERC20.sol";
import {IERC721} from "./IERC721.sol";
import {IERC1155} from "./IERC1155.sol";

/// @title Withdrawable
/// @author kevincharm
abstract contract Withdrawable {
    event ETHWithdrawn(address to, uint256 amount);
    event ERC20Withdrawn(address to, address token, uint256 amount);
    event ERC721Withdrawn(address to, address token, uint256 tokenId);
    event ERC1155Withdrawn(
        address to,
        address token,
        uint256 tokenId,
        uint256 amount
    );

    function _authoriseWithdrawal() internal virtual;

    function withdrawETH(address to, uint256 amount) external {
        _authoriseWithdrawal();
        payable(to).transfer(amount);
        emit ETHWithdrawn(to, amount);
    }

    function withdrawERC20(address token, address to, uint256 amount) external {
        _authoriseWithdrawal();
        IERC20(token).transfer(to, amount);
        emit ERC20Withdrawn(to, token, amount);
    }

    function withdrawERC721(
        address token,
        address to,
        uint256 tokenId
    ) external {
        _authoriseWithdrawal();
        IERC721(token).safeTransferFrom(address(this), to, tokenId);
        emit ERC721Withdrawn(to, token, tokenId);
    }

    function withdrawERC1155(
        address token,
        address to,
        uint256 tokenId,
        uint256 amount
    ) external {
        _authoriseWithdrawal();
        IERC1155(token).safeTransferFrom(
            address(this),
            to,
            tokenId,
            amount,
            bytes("")
        );
        emit ERC1155Withdrawn(to, token, tokenId, amount);
    }
}

