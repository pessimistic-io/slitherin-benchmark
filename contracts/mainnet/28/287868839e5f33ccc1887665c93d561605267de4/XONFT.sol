// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Ownable} from "./Ownable.sol";
import {ERC1155} from "./ERC1155.sol";
import {XOGame} from "./XOGame.sol";

contract XONFT is Ownable, ERC1155("https://xo.w1nt3r.xyz/api/token") {
    XOGame private immutable game;
    uint256 public immutable price = 0.005 ether;

    constructor(XOGame _game) payable {
        game = _game;
    }

    function mint(uint256 amount) public payable {
        require(msg.value == price * amount, "Invalid amount");

        (bool success, bytes memory err) = address(game).call{value: msg.value}("");
        require(success, string(err));

        _mint(msg.sender, 1, amount, "");
    }

    function setURI(string memory uri) public onlyOwner {
        _setURI(uri);
    }
}

