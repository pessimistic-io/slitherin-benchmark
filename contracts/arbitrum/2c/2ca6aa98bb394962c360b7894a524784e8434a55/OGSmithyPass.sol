// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "./Tiny1155NTT.sol";
import "./Recoverable.sol";
import "./TinyOwnable.sol";
import "./ERC20.sol";

abstract contract Security {
    modifier onlySender() {
        require(tx.origin == msg.sender, "The caller is another contract");
        _;
    }
}

contract OGSmithyPass is Tiny1155NTT, Ownable, Recoverable, Security {
    address public magicAddress;
    bool public mintIsActive = false;
    uint256 public cost;

    constructor() Tiny1155NTT("OGSmithyPass", "SMITHOGP") {}

    function mint(uint256 _qty) external onlySender {
        require(mintIsActive, "Ser Broke is sleeping");
        require(cost != 0, "Cost not set");
        uint256 _cost = _qty * cost;
        ERC20(magicAddress).transferFrom(msg.sender, address(this), _cost);
        _mint(msg.sender, 0, _qty);
        totalSupply += _qty;
    }

    function adminMint(address _target, uint256 _qty) external onlyOwner {
        _mint(_target, 0, _qty);
        totalSupply += _qty;
    }

    function setMagicAddress(address _magicAddress) external onlyOwner {
        magicAddress = _magicAddress;
    }

    function setCost(uint256 _cost) external onlyOwner {
        cost = _cost;
    }

    function setBaseTokenURI(string memory baseURI) external onlyOwner {
        _setBaseTokenURI(baseURI);
    }

    function toggleSale() public onlyOwner {
        mintIsActive = !mintIsActive;
    }

    function uri(uint256 id) public view returns (string memory) {
        require(id <= 0, "URI doesn't exist");
        return string(abi.encodePacked(baseTokenURI, _toString(id)));
    }
}

