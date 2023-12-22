// SPDX-License-Identifier: MIT

pragma solidity ^0.8.1;

import "./ERC20_IERC20.sol";
import "./Strings.sol";
import "./ERC721URIStorage.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./MerkleProof.sol";


contract ChowChowNFT is ERC721URIStorage, Ownable, ReentrancyGuard{
    string private _collectionURI;
    string public baseURI;

    uint256 immutable public maxGiftMintId = 10;
    uint256 public giftMintId = 1;

    uint256 immutable public maxWhitelistId = 300;
    uint256 public whitelistId = 11;
    uint256 public constant WHITELIST_SALE_PRICE = 0.00 ether;

    uint256 immutable public maxPublicMint = 2500;
    uint256 public publicMintId = 301;
    uint256 public constant PUBLIC_SALE_PRICE = 0.04 ether;

    // used to validate whitelists
    bytes32 public giftMerkleRoot;
    bytes32 public whitelistMerkleRoot;

    // keep track of those on whitelist who have claimed their NFT
    mapping(address => bool) public claimed;

    constructor(string memory _baseURI, string memory collectionURI) ERC721("ChowChowNFT", "NFT") {
        setBaseURI(_baseURI);
        setCollectionURI(collectionURI);
    }

    /**
     * @dev validates merkleProof
     */
    modifier isValidMerkleProof(bytes32[] calldata merkleProof, bytes32 root) {
        require(
            MerkleProof.verify(
                merkleProof,
                root,
                keccak256(abi.encodePacked(msg.sender))
            ),
            "Address does not exist in list"
        );
        _;
    }

    modifier isCorrectPayment(uint256 price, uint256 numberOfTokens) {
        require(
            price * numberOfTokens == msg.value,
            "Incorrect ETH value sent"
        );
        _;
    }

    modifier canMint(uint256 numberOfTokens) {
        require(
            publicMintId + numberOfTokens <= maxPublicMint,
            "Not enough tokens remaining to mint"
        );
        _;
    }

    // ============ PUBLIC FUNCTIONS FOR MINTING ============

    function mintGift(
        bytes32[] calldata merkleProof
    )
        public
        isValidMerkleProof(merkleProof, giftMerkleRoot)
        nonReentrant
    {
      require(giftMintId <= maxGiftMintId);
      require(!claimed[msg.sender], "NFT is already claimed by this wallet");
      _mint(msg.sender, giftMintId);
      giftMintId++;
    }

    function mintWhitelist(
      bytes32[] calldata merkleProof
    )
        public
        isValidMerkleProof(merkleProof, whitelistMerkleRoot)
        nonReentrant
    {
        require(whitelistId <= maxWhitelistId, "minted the maximum # of whitelist tokens");
        require(!claimed[msg.sender], "NFT is already claimed by this wallet");
        _mint(msg.sender, whitelistId);
        whitelistId++;
        claimed[msg.sender] = true;
    }

    function publicMint(
      uint256 numberOfTokens
    )
        public
        payable
        isCorrectPayment(PUBLIC_SALE_PRICE, numberOfTokens)
        canMint(numberOfTokens)
        nonReentrant
    {
        for (uint256 i = 0; i < numberOfTokens; i++) {
            _mint(msg.sender, publicMintId);
            publicMintId++;
        }
    }

    // ============ PUBLIC READ-ONLY FUNCTIONS ============
    function tokenURI(uint256 tokenId)
      public
      view
      virtual
      override
      returns (string memory)
    {
      require(_exists(tokenId), "ERC721Metadata: query for nonexistent token");
      return string(abi.encodePacked(baseURI, Strings.toString(tokenId), ".json"));
    }

    /**
    * @dev collection URI for marketplace display
    */
    function contractURI() public view returns (string memory) {
        return _collectionURI;
    }

    function currentId() public view returns (uint256) {
	return publicMintId;
    }

    // ============ OWNER-ONLY ADMIN FUNCTIONS ============
    function setBaseURI(string memory _baseURI) public onlyOwner {
      baseURI = _baseURI;
    }

    /**
    * @dev set collection URI for marketplace display
    */
    function setCollectionURI(string memory collectionURI) internal virtual onlyOwner {
        _collectionURI = collectionURI;
    }

    function setGiftMerkleRoot(bytes32 merkleRoot) external onlyOwner {
        giftMerkleRoot = merkleRoot;
    }

    function setWhitelistMerkleRoot(bytes32 merkleRoot) external onlyOwner {
        whitelistMerkleRoot = merkleRoot;
    }

    /**
     * @dev withdraw funds for to specified account
     */
    function withdraw() public onlyOwner {
        uint256 balance = address(this).balance;
        payable(msg.sender).transfer(balance);
    }

    function withdrawTokens(IERC20 token) public onlyOwner {
        uint256 balance = token.balanceOf(address(this));
        token.transfer(msg.sender, balance);
    }
}

