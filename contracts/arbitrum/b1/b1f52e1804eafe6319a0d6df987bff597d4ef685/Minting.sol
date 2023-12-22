// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./ERC1155.sol";
import "./Ownable.sol";

contract TADMinting is ERC1155, Ownable {
    uint256 public constant bannerID = 420;
    uint256 public mintCost = 0.01 ether;
    uint256 public totalSupply = 1000;

    constructor()
        ERC1155("ipfs://Qmdo5szxyQdo4LSyDq55F6gtLcbuGcXw54N6YiYoKRbjf4")
    {}

    function setURI(string memory newuri) public onlyOwner {
        _setURI(newuri);
    }

    function mint(uint256 amount) public payable {
        require(totalSupply > 0, "No more B@nners available to mint");
        require(msg.value >= mintCost * amount, "Not enough ether");
        require(totalSupply - amount > 0, "Not enough b@nners available");

        totalSupply = totalSupply - amount;

        _mint(msg.sender, bannerID, amount, "");
    }

    function getTotalMinted() public view returns (uint256) {
        return (1000 - totalSupply);
    }

    function numberOfNFTsInWallet() public view returns (uint256) {
        return balanceOf(msg.sender, bannerID);
    }

    function transfer(address _to) external payable onlyOwner {
        return payable(_to).transfer(address(this).balance);
    }
}

