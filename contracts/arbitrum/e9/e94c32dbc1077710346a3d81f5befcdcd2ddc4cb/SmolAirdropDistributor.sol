// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./IERC20.sol";
import "./Ownable.sol";
import "./Smols.sol";

contract SmolAirdropDistributor is Ownable {
    Smols public smol;
    IERC20 public moeta;
    mapping(uint256 => bool) public claimed;
    uint256 public amountPerNft; // tokens
    bool public airdropEnabled;

    constructor(address _smol, address _moeta) {
        smol = Smols(_smol); // migrated smols
        moeta = IERC20(_moeta);
        amountPerNft = ((moeta.totalSupply() * 5) / 100) / 12727; // 5% of total supply
        airdropEnabled = false;
    }

    function claim(uint256[] memory tokenIds) public {
        require(airdropEnabled, "Airdrop not enabled");
        uint256 amount = 0;
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            require(smol.ownerOf(tokenId) == msg.sender, "Not owner");
            require(!hasClaimed(tokenId), "Already claimed");
            claimed[tokenId] = true;
            amount += amountPerNft;
        }

        if (amount > 0) IERC20(moeta).transfer(msg.sender, amount);
    }

    function hasClaimed(uint256 tokenId) public view returns (bool) {
        return claimed[tokenId];
    }

    function claimableByOwner(
        address _owner
    ) public view returns (uint256[] memory) {
        uint256[] memory owned = smol.walletOfOwner(_owner);
        uint256[] memory claimable;

        uint256 claimableCount = 0;
        for (uint256 i = 0; i < owned.length; i++) {
            uint256 tokenId = owned[i];
            if (!hasClaimed(tokenId)) {
                claimable[claimableCount] = tokenId;
                claimableCount++;
            }
        }
        return claimable;
    }

    function setAirdropEnabled(bool _airdropEnabled) public onlyOwner {
        airdropEnabled = _airdropEnabled;
    }

    function updateAmountPerNft(uint256 _amountPerNft) public onlyOwner {
        amountPerNft = _amountPerNft;
    }

    function ownerWithdraw(uint256 _amount) public onlyOwner {
        IERC20(moeta).transfer(msg.sender, _amount);
    }

    function updateMoeta(address _moeta) public onlyOwner {
        moeta = IERC20(_moeta);
    }
}

