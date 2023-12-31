// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.7;
import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./ERC721A.sol";
import "./Strings.sol";
import "./SafeMath.sol";

contract LordUniverse is ERC721A, Ownable, ReentrancyGuard {
    using Strings for uint256;
    using SafeMath for uint256;
    using SafeMath for uint8;

    uint256 public constant mintLimit = 10;
    uint256 public constant mintLimitForWL = 2;
    uint256 public constant giveawaySupply = 77;
    uint256 public constant maxSupply = 7777;
    uint256 public mintPrice = 0.005 ether;
    uint256 public maxPerAddressDuringMint;

    bool public saleStarted = false;
    bool public presaleStarted = false;
    bool public revealed = false;

    string private baseExtension = ".json";
    string private baseURI;
    string private notRevealedURI;

    bytes32 private _merkleRoot;

    // Team wallet
    address[] private _royaltyAddresses = [
        0xC1d8eAD34882129f7F439855B336D23053D9e793, // Wallet 1 address
        0xb20F2a4601aED75B886CC5B84E28a0D65a7Bfd48 // Wallet 2 address
    ];

    mapping(address => uint256) private _royaltyShares;

    constructor(
        uint256 maxBatchSize_,
        string memory baseURI_,
        string memory notRevealedURI_
    ) ERC721A("Lord Universe", "LU") {
        maxPerAddressDuringMint = maxBatchSize_;
        baseURI = baseURI_;
        notRevealedURI = notRevealedURI_;

        _royaltyShares[_royaltyAddresses[0]] = 97; // Royalty for Wallet 1
        _royaltyShares[_royaltyAddresses[1]] = 3; // Royalty for Wallet 2
    }

    modifier callerIsUser() {
        require(tx.origin == msg.sender, "The caller is another contract");
        _;
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return baseURI;
    }

    /**
     * @dev Mint NFTs for giveway
     */
    function mintForGiveaway() external onlyOwner {
        require(totalSupply() == 0, "Mint already started");

        uint256 numChunks = giveawaySupply / maxPerAddressDuringMint;
        for (uint256 i = 0; i < numChunks; i++) {
            _safeMint(_royaltyAddresses[0], maxPerAddressDuringMint);
        }

        uint256 numModules = giveawaySupply % maxPerAddressDuringMint;
        if (numModules > 0) {
            _safeMint(_royaltyAddresses[0], numModules);
        }
    }

    /**
     * @dev   Admin mint for allocated NFTs
     * @param _amount Number of NFTs to mint
     * @param _to NFT receiver
     */
    function mintAdmin(uint256 _amount, address _to) external onlyOwner {
        require(totalSupply() >= giveawaySupply, "Giveaway not minted");
        require(totalSupply() + _amount <= maxSupply, "Max supply reached");

        uint256 numChunks = _amount / maxPerAddressDuringMint;
        for (uint256 i = 0; i < numChunks; i++) {
            _safeMint(_to, maxPerAddressDuringMint);
        }

        uint256 numModules = _amount % maxPerAddressDuringMint;
        if (numModules > 0) {
            _safeMint(_to, numModules);
        }
    }

    /**
     * @param _account Leaf for MerkleTree
     */
    function _leaf(address _account) private pure returns (bytes32) {
        return keccak256(abi.encodePacked(_account));
    }

    function _verifyWhitelist(bytes32 leaf, bytes32[] memory _proof)
        private
        view
        returns (bool)
    {
        bytes32 computedHash = leaf;

        for (uint256 i = 0; i < _proof.length; i++) {
            bytes32 proofElement = _proof[i];

            if (computedHash < proofElement) {
                computedHash = keccak256(
                    abi.encodePacked(computedHash, proofElement)
                );
            } else {
                computedHash = keccak256(
                    abi.encodePacked(proofElement, computedHash)
                );
            }
        }

        return computedHash == _merkleRoot;
    }

    /**
     * @param _amount Number of nfts to mint for whitelist
     * @param _proof Array of values generated by Merkle tree
     */
    function mintWL(uint256 _amount, bytes32[] memory _proof) external payable {
        require(presaleStarted, "Not started presale mint");
        require(totalSupply() >= giveawaySupply, "Giveaway not minted");
        require(
            _verifyWhitelist(_leaf(msg.sender), _proof) == true,
            "Invalid Address"
        );
        require(
            _amount > 0 && numberMinted(msg.sender) + _amount <= mintLimitForWL,
            "Max limit per wallet exceeded"
        );
        if (msg.sender != owner()) {
            require(msg.value >= mintPrice * _amount, "Need to send more ETH");
        }

        _safeMint(msg.sender, _amount);
        _refundIfOver(mintPrice * _amount);
    }

    /**
     * @param _amount numbers of NFT to mint for public sale
     */
    function mintPublicSale(uint256 _amount) external payable callerIsUser {
        require(saleStarted, "Not started public mint");
        require(totalSupply() >= giveawaySupply, "Giveaway not minted");
        require(totalSupply() + _amount <= maxSupply, "Reached max supply");
        require(_amount <= mintLimit, "Exceeds max mint limit");

        if (msg.sender != owner()) {
            require(msg.value >= mintPrice * _amount, "Need to send more ETH");
        }

        uint256 numChunks = _amount / maxPerAddressDuringMint;
        for (uint256 i = 0; i < numChunks; i++) {
            _safeMint(msg.sender, maxPerAddressDuringMint);
        }

        uint256 numModules = _amount % maxPerAddressDuringMint;
        if (numModules > 0) {
            _safeMint(msg.sender, numModules);
        }
        _refundIfOver(mintPrice * _amount);
    }

    function _refundIfOver(uint256 _price) private {
        if (msg.value > _price) {
            payable(msg.sender).transfer(msg.value - _price);
        }
    }

    /**
     * Override tokenURI
     */
    function tokenURI(uint256 _tokenId)
        public
        view
        virtual
        override
        returns (string memory)
    {
        require(_exists(_tokenId), "Not exist token");

        if (revealed == false) {
            return notRevealedURI;
        } else {
            string memory currentBaseURI = _baseURI();
            return
                bytes(currentBaseURI).length > 0
                    ? string(
                        abi.encodePacked(
                            currentBaseURI,
                            _tokenId.toString(),
                            baseExtension
                        )
                    )
                    : "";
        }
    }

    function withdraw() external onlyOwner nonReentrant {
        require(address(this).balance > 0, "Empty balance");
        uint256 balance = address(this).balance;

        for (uint256 i = 0; i < _royaltyAddresses.length; i++) {
            payable(_royaltyAddresses[i]).transfer(
                balance.div(100).mul(_royaltyShares[_royaltyAddresses[i]])
            );
        }
    }

    function setSaleStarted(bool _hasStarted) external onlyOwner {
        require(saleStarted != _hasStarted, "Already initialized");
        saleStarted = _hasStarted;
    }

    function setPresaleStarted(bool _hasStarted) external onlyOwner {
        require(presaleStarted != _hasStarted, "Already initialized");
        presaleStarted = _hasStarted;
    }

    function setBaseURI(string memory _newBaseURI) public onlyOwner {
        baseURI = _newBaseURI;
    }

    function setMintPrice(uint256 _mintPrice) public onlyOwner {
        mintPrice = _mintPrice;
    }

    function reveal() public onlyOwner {
        revealed = true;
    }

    function setNotRevealedURI(string memory _notRevealedURI) public onlyOwner {
        notRevealedURI = _notRevealedURI;
    }

    function setMerkleRoot(bytes32 _merkleRootValue)
        external
        onlyOwner
        returns (bytes32)
    {
        _merkleRoot = _merkleRootValue;
        return _merkleRoot;
    }

    function numberMinted(address owner) public view returns (uint256) {
        return _numberMinted(owner);
    }

    function getOwnershipData(uint256 tokenId)
        external
        view
        returns (TokenOwnership memory)
    {
        return ownershipOf(tokenId);
    }
}

