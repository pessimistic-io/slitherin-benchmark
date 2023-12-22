// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./ERC721A.sol";
import "./Mytho.sol";

contract Airdrop is Ownable {
    ERC721A private mytho = ERC721A(0xEa96874e438Fb31Bc7F86d05733E25782bE1b6ec);
    uint256 private current;

    constructor(uint256 _current) {
        current = _current;
    }

    function airdrop(address[] calldata user, uint256[] calldata amount) external onlyOwner {
        uint256 length = user.length;

        require(amount.length == length, "diff size");

        for (uint256 i; i < length;) {
            uint256 currentAmount = amount[i];
            address currentUser = user[i];

            for (uint256 j = 0; j < currentAmount; j++) {
                mytho.transferFrom(address(this), currentUser, current);
                current++;
            }

            unchecked {
                ++i;
            }
        }
    }

    function onERC721Received(address, address, uint256, bytes calldata) external returns (bytes4) {
        return bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"));
    }
}

