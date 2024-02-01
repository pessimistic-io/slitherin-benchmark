// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./IERC721.sol";
import "./IERC20.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./ERC721Enumerable.sol";
import "./ERC721.sol";

contract Motanka is ERC721Enumerable, Ownable, ReentrancyGuard {
	using Strings for uint256;

	string private _baseTokenURI = "https://coffee-neat-peafowl-302.mypinata.cloud/ipfs/QmNog8dL4g6G53z8fZnHM1VUaEtRz3Q7srdfjebkF8z7Xh/";
	string private _contractURI = "https://coffee-neat-peafowl-302.mypinata.cloud/ipfs/QmNog8dL4g6G53z8fZnHM1VUaEtRz3Q7srdfjebkF8z7Xh/";

	uint256 public maxSupply = 9999;

	uint256 public pricePerToken = 70000000000000000; //0.07 ETH

	bool public locked;

	constructor() ERC721("Motanka", "MTN") {}

	function burn(uint256 tokenId) public virtual {
		require(_isApprovedOrOwner(_msgSender(), tokenId), "caller is not owner nor approved");
		_burn(tokenId);
	}

	function exists(uint256 _tokenId) external view returns (bool) {
		return _exists(_tokenId);
	}

	function isApprovedOrOwner(address _spender, uint256 _tokenId) external view returns (bool) {
		return _isApprovedOrOwner(_spender, _tokenId);
	}

	function tokenURI(uint256 _tokenId) public view override returns (string memory) {
		require(_exists(_tokenId), "ERC721Metadata: URI query for nonexistent token");
		return string(abi.encodePacked(_baseTokenURI, _tokenId.toString(), ".json"));
	}

	function setBaseURI(string memory newBaseURI) public onlyOwner {
		require(!locked, "locked functions");
		_baseTokenURI = newBaseURI;
	}

	function setContractURI(string memory newuri) public onlyOwner {
		require(!locked, "locked functions");
		_contractURI = newuri;
	}

	function contractURI() public view returns (string memory) {
		return _contractURI;
	}

	function withdrawEarnings() public onlyOwner {
		payable(msg.sender).transfer(address(this).balance);
	}

	function reclaimERC20(IERC20 erc20Token) public onlyOwner {
		erc20Token.transfer(msg.sender, erc20Token.balanceOf(address(this)));
	}

	function changePrice(uint256 newPrice) external onlyOwner {
		pricePerToken = newPrice;
	}

	function decreaseMaxSupply(uint256 newMaxSupply) external onlyOwner {
		require(newMaxSupply < maxSupply, "you can only decrease it");
		maxSupply = newMaxSupply;
	}

	// and for the eternity....
	function lockMetadata() external onlyOwner {
		locked = true;
	}
}
