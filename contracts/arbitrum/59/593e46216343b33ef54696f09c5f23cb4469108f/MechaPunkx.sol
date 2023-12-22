// SPDX-License-Identifier: MIT
pragma solidity ^0.8.1;

import "./MechToken.sol";
import "./Ownable.sol";
import "./ERC721.sol";
import "./ERC721Enumerable.sol";
import "./ERC721Burnable.sol";
import "./ReentrancyGuard.sol";

/*
******************************
**** M E C H A P U N K X *****
******************************

MechaPunkx NFT (by LamboCorp)

ERC721
Yields ERC20 MECH Token to owner, allowing mint/distribution of more NFTs
Yields ERC20 LAMBO instead of MECH if converted
*/
contract MechaPunkx is ERC721, ERC721Enumerable, ERC721Burnable, Ownable, ReentrancyGuard {

	string public baseTokenURI = "https://lambo.lol/metadata/mechapunkx/";
	string public contractURI = "https://lambo.lol/mechapunkx/contract.json";

	uint256 public constant MAX_MECHAPUNKX = 7848;
	uint256 public saleRemaining = 200;
	uint256 public numMinted = 0;

	// For limiting maximum MechaPunkx mint per day
	bool public canBurn = true;
	bool private useDailyLimit = true;
	uint256 private dailyLimitStartDay = 0;
	uint256 private dailyLimitStartQuantity = 0;
	
	// Map MechaPunkx tokenId to start date of LAMBO yield
	mapping(uint256 => uint256) private lamboYieldStart;
	mapping(address => uint256) public allowlist;

	MechToken private mech;

	event ContractCreated(address newAddress);
	event AllowlistMint(uint256 quantity);
	event LamboYield(uint256 tokenId);
	event MechaPunkxGraveyard(uint256 tokenId);

	constructor() ERC721("MechaPunkx", "MECHAPUNKX") {
		mech = new MechToken(address(this));
		emit ContractCreated(address(mech));
	}

	// Cost in MECH Token required to claim a MechaPunkx NFT 
	// approx. # of days since launch
	function mintCost() public view returns (uint256) {

		// cost = min(100, max(9, day + 0))
		uint256 day = mech.maxEarned();
		if (day < 9) day = 9;
		else if (day > 100) day = 100;

		return day;
	}

	function mechTokenAddress() external view returns (address) {
		return address(mech);
	}

	function claimMechToken(uint256 tokenId) public {
		require(ownerOf(tokenId) == msg.sender, "Must be owner");
		require(lamboYieldStart[tokenId] == 0, "NFT yields LAMBO");
		mech.claim(tokenId);
	}

	function claimMechTokenAll() external {
		uint256[] memory tokens = tokensInWallet(msg.sender);
		for(uint256 i = 0; i < tokens.length; i++){
			// Skip any NFT yielding LAMBO
			if (lamboYieldStart[tokens[i]] == 0) {
				claimMechToken(tokens[i]);
			}
		}
	}

	function tokensInWallet(address owner) public view returns(uint256[] memory) {
		uint256 tokenCount = balanceOf(owner);
		uint256[] memory tokensId = new uint256[](tokenCount);
		for(uint256 i = 0; i < tokenCount; i++){
			tokensId[i] = tokenOfOwnerByIndex(owner, i);
		}
		return tokensId;
	}

	// Mint NFT for whitelist, 200 spots
	function mintAllowlist() external nonReentrant() {
		uint256 quantity = allowlist[msg.sender];
		require(quantity > 0, "Not on list");
		require(numMinted + quantity <= MAX_MECHAPUNKX, "All MechaPunkx claimed");
		allowlist[msg.sender] = 0;
		uint256 mintIndex = numMinted;
		numMinted += quantity;
		for (uint256 i = 0; i < quantity; i++) {
			_mint(msg.sender, mintIndex + i);
		}
		emit AllowlistMint(quantity);
	}

	// Public Sale, 200 spots
	function mintSale(uint256 quantity) external payable nonReentrant() {
		require(quantity > 0 && quantity <= 20, "Between 1 and 21");
		require(numMinted + quantity <= MAX_MECHAPUNKX, "Not enough remain");
		require((0.1 ether * quantity) <= msg.value, "Eth value incorrect");
		require(saleRemaining - quantity >= 0, "Not enough left for sale");

		saleRemaining -= quantity;
		uint256 mintIndex = numMinted;
		numMinted += quantity;

		for(uint i = 0; i < quantity; i++) {
			_mint(msg.sender, mintIndex + i);
		}
	}

	// Mint NFT by burning MECH
	function mintNFT() external nonReentrant() {
		require(numMinted + 1 <= MAX_MECHAPUNKX, "All MechaPunkx claimed.");

		if (useDailyLimit) {
			// At most, 100 MechaPunkx per day can be minted, starting once 500 minted
			uint256 currentDay = mech.maxEarned();
			uint256 nDaysPassed = currentDay - dailyLimitStartDay;

			if (numMinted > 500) {
				if (nDaysPassed < 1) {
					uint256 nMintedToday = numMinted - dailyLimitStartQuantity;
					require(nMintedToday < 100, "Try again tomorrow, limit of 100 MechaPunkx already minted today");
				}
				else {
					// If more than 1 day since start of last interval, reset daily limit
					dailyLimitStartQuantity = numMinted;
					dailyLimitStartDay = currentDay;
				}
			}
		}
		
		uint256 cost = mintCost() * (10**18);
		uint256 mechBalance = mech.balanceOf(msg.sender);
		require(mechBalance >= cost, "Not enough MECH");

		uint256 allowance = mech.allowance(msg.sender, address(this));
		require(allowance >= cost, "Needs approval to spend MECH");

		uint256 mintIndex = numMinted;
		numMinted += 1;
		mech.burnFrom(msg.sender, cost);
		// Calls _beforeTokenTransfer hook to start earning
		_mint(msg.sender, mintIndex);
	}

	// Burn NFT, stop accumulating MECH token, release unclaimed
	function burn(uint256 tokenId) public override nonReentrant() {
		require(ownerOf(tokenId) == msg.sender, "Must be owner");
		require(canBurn, "Burning NFT not allowed.");
		// Exclude the NFT from earning LAMBO
		lamboYieldStart[tokenId] = 0;
		emit MechaPunkxGraveyard(tokenId);
		mech.startEarning(tokenId);
		mech.burnNFT(tokenId, msg.sender);
		super._burn(tokenId);
	}
	
	// Permanently switch an NFT from yielding MECH Token to yielding LAMBO by spending 50 MECH
	function convertYieldToLambo(uint256 tokenId) external {
		require(ownerOf(tokenId) == msg.sender, "Must be owner");
		require(lamboYieldStart[tokenId] == 0, "Already yields LAMBO");

		uint256 burnRequirement = 50 * (10**18);
		uint256 mechBalance = mech.balanceOf(msg.sender);
		require(mechBalance >= burnRequirement, "Need 50 MECH");
		uint256 allowance = mech.allowance(msg.sender, address(this));
		require(allowance >= burnRequirement, "Needs approval to spend MECH");

		lamboYieldStart[tokenId] = block.timestamp;
		mech.burnFrom(msg.sender, burnRequirement);
		emit LamboYield(tokenId);
	}

	function isOverDailyLimit() external view returns (bool) {
		if (useDailyLimit) {
			// At most, 100 MechaPunkx per day can be minted (starting once 500 minted)
			uint256 currentDay = mech.maxEarned();
			uint256 nDaysPassed = currentDay - dailyLimitStartDay;
			if (numMinted > 500) {
				if (nDaysPassed < 1) {
					uint256 nMintedToday = numMinted - dailyLimitStartQuantity;
					if (nMintedToday >= 100) return true;
				}
			}
		}
		return false;
	}

	function seedAllowlist(address[] memory addresses, uint256 quantity) external onlyOwner {
		require(quantity >= 0, "Need positive quantity");
		for (uint256 i = 0; i < addresses.length; i++) {
			allowlist[addresses[i]] = quantity;
		}
	}

	function exists(uint256 tokenId) external view returns (bool) {
		return _exists(tokenId);
	}

	function setOptions(bool canBurnStatus, bool dailyLimitStatus) external onlyOwner {
		canBurn = canBurnStatus;
		useDailyLimit = dailyLimitStatus;
	}

	function nBurned() external view returns (uint256) {
		return numMinted - totalSupply();
	}

	function lamboYieldStartTime(uint256 tokenId) external view returns (uint256) {
		return lamboYieldStart[tokenId];
	}

	function yieldsLambo(uint256 tokenId) public view returns (bool) {
		return _exists(tokenId) && lamboYieldStart[tokenId] > 0;
	}

	// When transferring MechaPunkx NFT, void any unclaimed Mech Token
	function _beforeTokenTransfer(address _from, address _to, uint256 _tokenId) internal virtual override(ERC721, ERC721Enumerable) {
		if (numMinted < MAX_MECHAPUNKX || mech.maxEarned() < 500) mech.startEarning(_tokenId);
		super._beforeTokenTransfer(_from, _to, _tokenId);
	}

	function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC721Enumerable) returns (bool) {
		return super.supportsInterface(interfaceId);
	}

	function withdraw() external onlyOwner {
		uint256 balance = address(this).balance;
		payable(msg.sender).transfer(balance);
	}

	function _baseURI() internal view virtual override returns (string memory) {
		return baseTokenURI;
	}

	function setBaseURI(string memory baseURI) external onlyOwner {
		baseTokenURI = baseURI;
	}
}
