// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import "./IERC721Metadata.sol";
import "./ERC721.sol";
import "./IERC20Metadata.sol";

contract CnyPocket is ERC721 {
	IERC20Metadata usdc;
	uint8 usdc_decimals;
	uint256 counter;
	uint64 conv_rate = 12787; // 100000 / 7.82

	// tokenId -> smallest denom of USDC contract
	mapping(uint256 => uint256) public usdc_balance;

	constructor(address _usdc) ERC721("CnyPocket", "CNY") {
		usdc = IERC20Metadata(_usdc);
		usdc_decimals = usdc.decimals();
		counter = 0;
	}

	// assumes that owner already gave approval to his USDC to this contract
	function safeMint(address to, uint256 hkd_amount) public {
		counter += 1; // what you gonna do, overflow uint256?
		uint256 tokenId = counter;

		uint256 usdc_amount = hkd_amount * conv_rate * 10**(usdc_decimals - 5);
		require(usdc.transferFrom(
			msg.sender,
			address(this),
			usdc_amount 
		), "funding failed");
		usdc_balance[tokenId] = usdc_amount;
        _safeMint(to, tokenId);
    }

	function unwrap(uint256 tokenId) public {
		require(ownerOf(tokenId) == msg.sender, "not owner");
		uint256 amount = usdc_balance[tokenId];
		require(amount > 0, "already open");
		usdc_balance[tokenId] = 0;
		require(usdc.transfer(msg.sender, amount), "failed transfer");
	}

	function tokenURI(uint256 tokenId) public view override returns (string memory) {
		if (usdc_balance[tokenId] > 0) {
			return "ipfs://bafkreibcckeus3thrx4ugkl7h5qkklffx7snrpi7p7zmewonbxqxkpndw4";
		} else {
			return "ipfs://bafkreift6tjpdjlua7o5cxwkorj6nuop4qxqcrosvyvzzdabtlykpwhfki";
		}
	}

	function hkdContent(uint256 tokenId) public view returns (uint256) {
		uint256 balance = usdc_balance[tokenId];
		require(balance > 0, "zero");
		return balance / (10**(usdc_decimals - 5) * conv_rate);
	}
}

