// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./Ownable.sol";
import "./ERC721Enumerable.sol";

// Uncomment this line to use console.log
// import "hardhat/console.sol";

contract SGT is Ownable, ERC721Enumerable {

    uint256 s_pass_price = 0 ether;

    uint256 s_max_per_wallet = 1;

    uint256 public s_total_supply;

	string private _baseTokenURI = "https://gateway.pinata.cloud/ipfs/QmUUCDGWoHfoaVMN5LncqFLoJvkrCW1Znz2qLnQFsvPbgZ";

    event Minted(address user, uint timestamp);

    constructor()ERC721("Story governance token test","SGT") payable {
        
    }
    
     /**
	 * Mints pass token
	 */
    function mintPass() external payable {
        require(msg.value >= s_pass_price, "You don't have enought funds");
        require(balanceOf(msg.sender) < s_max_per_wallet, "You can't buy more than 1 mint pass token");

        _safeMint(msg.sender, s_total_supply);
        s_total_supply++;
        emit Minted(msg.sender, block.timestamp);
    }

    /**
	 * Sets new token price
	 * @notice only owner
	 */
	function setTokenPrice(uint256 _price) external onlyOwner {
	    s_pass_price = _price;
	}

     /**
	 * Sets new max per wallet value
	 * @notice only owner
	 */
	function setMaxPerWallet(uint256 _value) external onlyOwner {
	    s_max_per_wallet = _value;
	}

	function tokenURI(uint256) public view virtual override returns (string memory) {
        return _baseTokenURI;
    }

    function setBaseURI(string calldata baseURI) external onlyOwner {
       _baseTokenURI = baseURI;
    }

    /**
	 * Withdraw ETH from contract to owner address
	 * @notice only owner can withdraw
	 */
	function withdrawETH() external onlyOwner {
		(bool sent, ) = msg.sender.call{value: address(this).balance}('');
		require(sent, 'Failed to withdraw ETH');
	}
}

