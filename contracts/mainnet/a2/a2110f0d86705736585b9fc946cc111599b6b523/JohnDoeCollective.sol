// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./ERC721A.sol";
import "./ReentrancyGuard.sol";
import "./MerkleProof.sol";

contract JohnDoeCollective is ERC721A, ReentrancyGuard {
    using Strings for uint256;
	
	// Token Info
	uint256 public MAX_SUPPLY = 250;
	uint256 public PRICE = .01 ether;
	uint256 public MAX_VOLUME_MINTABLE  = 100;

    // Base URI
    string private _baseURIextended;

	// AllowList
	mapping(address => uint8) private _claimList;
	
	// PreSale - PublicSales
	uint8 private _state = 0;
	
	// Whitelist
	bytes32 public merkleRoot = 0x0000000000000000000000000000000000000000000000000000000000000000;
	
	// Owners
	address private owner0 = 0xe8dEe1F812194521d5Cd74BA8b9E21b2cdc048C4;
	address private owner1 = 0x91587758Ab2Ae704887Be04b2706C0aFA5583dC3;
	
	// Modifiers
	modifier isRealUser() {
		require(msg.sender == tx.origin, "Sorry, you do not have the permission todo that.");
		_;
	}
	modifier isOwner() {
        require(msg.sender == owner0 || msg.sender == owner1, "You are not an owner");
        _;
    }
	
    constructor() ERC721A('John Doe Collective', 'JDC', 3) {
	}
	
	function changeSupply(uint256 num) external isOwner() {
		MAX_SUPPLY = num;
	}

    function setBaseURI(string memory baseURI_) external isOwner() {
        _baseURIextended = baseURI_;
    }
    
    function _baseURI() internal view virtual override returns (string memory) {
        return _baseURIextended;
    }
	
	function setVolumeMintable(uint256 maxMintable) external isOwner {
		MAX_VOLUME_MINTABLE = maxMintable;
	}
	
	function getTotalSupply() public view returns (uint256) {
		return totalSupply();
	}
	
	function getTokenByOwner(address _owner) public view returns (uint256[] memory) {
		uint256 tokenCount = balanceOf(_owner);
		uint256[] memory tokenIds = new uint256[](tokenCount);
		for (uint256 i; i < tokenCount; i++) {
			tokenIds[i] = tokenOfOwnerByIndex(_owner, i);
		}
		return tokenIds;
	}
	
	function setProof(bytes32 newRoot) public isOwner() {
		merkleRoot = newRoot;
	}

	function setState(uint8 newState) public isOwner() {
		_state = newState;
	}
	
	function withdraw() public isOwner() nonReentrant {
		uint256 currentBalance = address(this).balance;
		require(payable(owner0).send(currentBalance), "Wrong.");
	}
	
	function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
		require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token");
		if(tokenId < MAX_SUPPLY) {
			return string(abi.encodePacked(_baseURI(), tokenId.toString(), ".json"));
		} else {
			return "ERC721Metadata: URI query for nonexistent token - Invalid token ID";
		}
	}
	
	function mintPresale(uint8 TOKENS_TO_MINT, bytes32[] calldata _merkleProof) public payable isRealUser nonReentrant {
		require(_state == 1, "Sorry, pre-sales is not active yet.");
		require((totalSupply() + TOKENS_TO_MINT) <= MAX_VOLUME_MINTABLE , "Exceeding max supply");
		require(TOKENS_TO_MINT <= 1 && TOKENS_TO_MINT > 0, "Sorry, you are trying to mint too many tokens at one time");
		require(_claimList[msg.sender] <= 8, "Address has already claimed");
		
		bytes32 proof = keccak256(abi.encodePacked(msg.sender));
		require(MerkleProof.verify(_merkleProof, merkleRoot, proof), 'Invalid proof.');
		
		_claimList[msg.sender] += TOKENS_TO_MINT;
		_mint(TOKENS_TO_MINT, msg.sender);
	}
	
	function mintPaid(uint8 TOKENS_TO_MINT) public payable isRealUser nonReentrant {
		require(_state == 3, "Sorry, public-sales are not active yet.");
		require((totalSupply() + TOKENS_TO_MINT) <= MAX_VOLUME_MINTABLE , "Exceeding max supply");
		require(TOKENS_TO_MINT <= 1 && TOKENS_TO_MINT > 0, "Sorry, you are trying to mint too many tokens at one time");
		require(PRICE*TOKENS_TO_MINT <= msg.value, "Sorry, you did not sent the required amount of ETH");
		require(_claimList[msg.sender] <= 20, "Address has already claimed");
		
		_claimList[msg.sender] += TOKENS_TO_MINT;
		_mint(TOKENS_TO_MINT, msg.sender);
	}
	
	function mintPublic(uint8 TOKENS_TO_MINT) public payable isRealUser nonReentrant {
		require(_state == 2, "Sorry, public-sales are not active yet.");
		require((totalSupply() + TOKENS_TO_MINT) <= MAX_VOLUME_MINTABLE , "Exceeding max supply");
		require(TOKENS_TO_MINT <= 1 && TOKENS_TO_MINT > 0, "Sorry, you are trying to mint too many tokens at one time");
		require(_claimList[msg.sender] <= 20, "Address has already claimed");
		
		_claimList[msg.sender] += TOKENS_TO_MINT;
		_mint(TOKENS_TO_MINT, msg.sender);
	}
    
	function reserveToken(uint256 num) public isOwner() {
		require((totalSupply() + num) <= MAX_SUPPLY, "Exceeding max supply");
		_mint(num, msg.sender);
	}
	
	function airdropToken(uint256 num, address recipient) public isOwner() {
		require((totalSupply() + num) <= MAX_SUPPLY, "Exceeding max supply");
		_mint(num, recipient);
	}
	
	function airdropTokenToMultipleRecipient(address[] memory recipients) external isOwner() {
		require((totalSupply() + recipients.length) <= MAX_SUPPLY, "Exceeding max supply");
		for (uint256 i = 0; i < recipients.length; i++) {
			airdropToken(1, recipients[i]);
		}
	}
	
	function _mint(uint256 num, address recipient) internal {
		_safeMint(recipient, num);
	}
}
