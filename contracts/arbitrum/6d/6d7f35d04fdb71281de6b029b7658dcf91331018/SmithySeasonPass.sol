// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "./Tiny1155NTTBM.sol";
import "./TinyOwnable.sol";
import "./Recoverable.sol";

abstract contract Security {
    modifier onlySender() {
        require(tx.origin == msg.sender, "The caller is another contract");
        _;
    }
}

contract SmithySeasonPass is Tiny1155NTT, Ownable, Security {
    bool public mintIsActive;
    uint256 public currentSeason = 1;
    uint256 public cost;

    constructor() Tiny1155NTT("SmithySeasonPass", "SSP") {}

    function mint(uint256 _qty) external payable onlySender {
        require(mintIsActive, "Ser Broke is sleeping");
        require(cost != 0, "Cost not set");
        require(_qty * cost == msg.value, "Not enough eth");
        _mint(msg.sender, currentSeason, _qty);
    }

    function adminMint(address _target, uint256[] calldata _ids, uint256[] calldata _qty) external onlyOwner {
        _batchMint(_target, _ids, _qty);
    }

    function setCost(uint256 _cost) external onlyOwner {
        cost = _cost;
    }

    function setSeason(uint256 _season) external onlyOwner {
        currentSeason = _season;
    }

    function setBaseTokenURI(string memory baseURI) external onlyOwner {
        _setBaseTokenURI(baseURI);
    }

    function toggleSale() public onlyOwner {
        mintIsActive = !mintIsActive;
    }

    function uri(uint256 id) public view returns (string memory) {
        require(id + 1 <= currentSeason, "URI doesn't exist");
        return string(abi.encodePacked(baseTokenURI, _toString(id)));
    }
}

