// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "./ERC1155Gateway.sol";

interface IMintBurn1155 {
    function mint(
        address account,
        uint256 tokenId,
        uint256 amount
    ) external;

    function burn(
        address account,
        uint256 tokenId,
        uint256 amount
    ) external;
}

contract ERC1155Gateway_MintBurn is ERC1155Gateway {
    constructor(
        address anyCallProxy,
        uint256 flag,
        address token
    ) ERC1155Gateway(anyCallProxy, flag, token) {}

    function description() external pure returns (string memory) {
        return "ERC1155Gateway_MintBurn";
    }

    function _swapout(
        address sender,
        uint256 tokenId,
        uint256 amount
    ) internal virtual override returns (bool, bytes memory) {
        try IMintBurn1155(token).burn(sender, tokenId, amount) {
            return (true, "");
        } catch {
            return (false, "");
        }
    }

    function _swapin(
        uint256 tokenId,
        uint256 amount,
        address receiver,
        bytes memory extraMsg
    ) internal override returns (bool) {
        try IMintBurn1155(token).mint(receiver, tokenId, amount) {
            return true;
        } catch {
            return false;
        }
    }
}

