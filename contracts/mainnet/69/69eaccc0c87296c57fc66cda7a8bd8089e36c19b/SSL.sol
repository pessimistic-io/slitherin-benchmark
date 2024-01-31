// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC721.sol";
import "./Counters.sol";
import "./PullPayment.sol";
import "./Ownable.sol";

contract SSL is ERC721, PullPayment, Ownable {
	using Counters for Counters.Counter;
	Counters.Counter private currentTokenId;

	// Constants
	uint256 public constant TOTAL_SUPPLY = 10_000;
	uint256 public constant MINT_PRICE = 0.0000 ether;

	/// @dev Base token URI used as a prefix by tokenURI().
	string public baseTokenURI;

	constructor() ERC721("Super Skills League", "SSL") {
		baseTokenURI = "";
	}

	function mintTo(address recipient) public onlyOwner returns (uint256) {
		uint256 tokenId = currentTokenId.current();
    	require(tokenId < TOTAL_SUPPLY, "Max supply reached");
    	 //require(msg.value == MINT_PRICE, "Transaction value did not equal the mint price");

		currentTokenId.increment();
		uint256 newItemId = currentTokenId.current();
		_safeMint(recipient, newItemId);
		return newItemId;
	}

  /// @dev Returns an URI for a given token ID
  function _baseURI() internal view virtual override returns (string memory) {
    return baseTokenURI;
  }

  /// @dev Sets the base token URI prefix.
  function setBaseTokenURI(string memory _baseTokenURI) public onlyOwner {
    baseTokenURI = _baseTokenURI;
  }

  /// @dev Overridden in order to make it an onlyOwner function
  function withdrawPayments(address payable payee) public override onlyOwner virtual {
      super.withdrawPayments(payee);
  }
}
