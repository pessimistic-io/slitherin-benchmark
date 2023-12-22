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

contract SmithySeasonPassV2 is Tiny1155NTT, Ownable, Recoverable, Security {
    bool public mintIsActive;
    uint256 public currentSeason = 1;
    uint256 public cost;

    constructor() Tiny1155NTT("SmithySeasonPassV2", "SSPV2") {}

    function mintVault(uint256 _qty) external payable onlySender {
        require(mintIsActive, "Ser Broke is sleeping");
        require(cost != 0, "Cost not set");
        require(_qty != 0, "Minting nothing are you?");
        require(msg.value >= _qty * cost, "Not enough eth");
        require(vault != address(0), "Vault not set");
        payable(vault).transfer(msg.value);
        _mint(msg.sender, currentSeason, _qty);
    }

    function mint(uint256 _qty) external payable onlySender {
        require(mintIsActive, "Ser Broke is sleeping");
        require(cost != 0, "Cost not set");
        require(_qty != 0, "Minting nothing are you?");
        require(msg.value >= _qty * cost, "Not enough eth");
        _mint(msg.sender, currentSeason, _qty);
    }

    function airdrop(
        address[] calldata _target,
        uint256[] calldata _ids,
        uint256[] calldata _qty
    ) external onlyOwner {
        for (uint256 i = 0; i < _target.length;i++) {
            _mint(_target[i], _ids[i], _qty[i]);
        }
    }

    function adminMint(
        address _target,
        uint256 _id,
        uint256 _qty
    ) external onlyOwner {
        _mint(_target, _id, _qty);
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
        require(id <= currentSeason && id != 0, "URI doesn't exist");
        return string(abi.encodePacked(baseTokenURI, _toString(id)));
    }
}

