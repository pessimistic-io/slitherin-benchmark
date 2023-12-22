// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./ERC20.sol";
import "./Ownable.sol";
import "./Pausable.sol";
import "./HarvestToken.sol";

contract HarvestIncinerator is Ownable, Pausable {
    HarvestToken public hrvstToken;
    uint256 public pricePerHrvst; // e.g: 1 HRVST = 0.0001 ETH

    constructor(address _hrvstAddress, uint256 _pricePerHrvst) {
        hrvstToken = HarvestToken(_hrvstAddress);
        pricePerHrvst = _pricePerHrvst;
        _pause();
    }

    function paidBurn(uint _hrvstAmount) external whenNotPaused {
        require(_hrvstAmount > 0, "Amount must be greater than 0");
        require(_hrvstAmount <= hrvstToken.balanceOf(msg.sender), "Insuficient balance");

        // burn tokens
        hrvstToken.transferFrom(msg.sender, address(this), _hrvstAmount);
        hrvstToken.burn(_hrvstAmount);

        // pay user in ETH
        uint valToPay = (_hrvstAmount * pricePerHrvst) / 1 ether;
        payable(msg.sender).transfer(valToPay);
    }

    // ADMIN FUNCTIONS

    // set price per token onlyOwner
    function setPricePerHrvst(uint256 _pricePerHrvst) external onlyOwner {
        pricePerHrvst = _pricePerHrvst;
    }

    // toggle pause contract
    function togglePause() external onlyOwner {
        if (paused()) {
            _unpause();
        } else {
            _pause();
        }
    }

    // withdraw ETH onlyOwner
    function withdraw() external onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }

    // withdraw tokens onlyOwner
    function withdrawTokens(address _tokenAddress) external onlyOwner {
        ERC20 token = ERC20(_tokenAddress);
        token.transfer(owner(), token.balanceOf(address(this)));
    }

    // set token address onlyOwner
    function setTokenAddress(address _tokenAddress) external onlyOwner {
        hrvstToken = HarvestToken(_tokenAddress);
    }

    event Received(address, uint);
    receive() external payable {
        emit Received(msg.sender, msg.value);
    }
}

