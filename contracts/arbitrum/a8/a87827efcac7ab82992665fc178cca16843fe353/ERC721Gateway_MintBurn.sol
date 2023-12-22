// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "./ERC721Gateway.sol";

interface IMintBurn721 {
    function ownerOf(uint256 tokenId) external view returns (address owner);

    function mint(address account, uint256 tokenId) external;

    function burn(uint256 tokenId) external;
}

contract ERC721Gateway_MintBurn is ERC721Gateway {
    constructor(
        address anyCallProxy,
        uint256 flag,
        address token
    ) ERC721Gateway(anyCallProxy, flag, token) {}

    function description() external pure returns (string memory) {
        return "ERC721Gateway_MintBurn";
    }

    function _swapout(uint256 tokenId)
        internal
        virtual
        override
        returns (bool, bytes memory)
    {
        require(
            IMintBurn721(token).ownerOf(tokenId) == msg.sender,
            "not allowed"
        );
        try IMintBurn721(token).burn(tokenId) {
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
        try IMintBurn721(token).mint(receiver, tokenId) {
            return true;
        } catch {
            return false;
        }
    }
}

