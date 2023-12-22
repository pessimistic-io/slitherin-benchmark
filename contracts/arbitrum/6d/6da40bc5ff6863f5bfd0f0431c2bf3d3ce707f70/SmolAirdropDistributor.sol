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
    }

    function claim(uint256[] memory tokenIds) public onlyAirdropEnabled {
        address user = msg.sender;
        uint256 amount = 0;
        for (uint256 i = 0; i < tokenIds.length; i++) {
            amount += _claim(tokenIds[i], user);
        }

        if (amount > 0) IERC20(moeta).transfer(user, amount);
    }

    function claimId(uint256 tokenId) public onlyAirdropEnabled {
        address user = msg.sender;
        uint256 amount = _claim(tokenId, user);
        if (amount > 0) IERC20(moeta).transfer(user, amount);
    }

    function _claim(uint256 tokenId, address user) internal returns (uint256) {
        require(smol.ownerOf(tokenId) == user, "Not owner");
        require(!hasClaimed(tokenId), "Already claimed");
        claimed[tokenId] = true;
        return amountPerNft;
    }

    function hasClaimed(uint256 tokenId) public view returns (bool) {
        return claimed[tokenId];
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

    function updateMoetaToken(address _moeta) public onlyOwner {
        moeta = IERC20(_moeta);
    }

    modifier onlyAirdropEnabled() {
        require(airdropEnabled, "Airdrop not enabled");
        require(moeta.balanceOf(address(this)) > 0, "No tokens left");
        _;
    }
}

