// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./ERC721Enumerable.sol";
import "./MerkleProof.sol";
import "./Ownable.sol";
import "./Counters.sol";
import "./Strings.sol";

contract KKMonkey is ERC721Enumerable, Ownable {
    using Strings for uint256;

    bool public _isSaleActive = false;
    bool public _revealed = false;

    uint256 public constant MAX_SUPPLY = 7777;
    uint256 public constant MAX_MINT_PER_USER = 2;
    uint256 public mintPrice = 0.01 ether;

    bytes32 public merkleRoot;
    string baseURI;
    string public notRevealedUri;

    using Counters for Counters.Counter;

    Counters.Counter private _tokenIdCounter;
    mapping(uint256 => string) private _tokenURIs;
    mapping(address => uint256) public mintedAmount;

    constructor() ERC721("KKMonkey", "KKMonkey") {}

    function setMerkleRoot(bytes32 _merkleRoot) external onlyOwner {
        merkleRoot = _merkleRoot;
    }

    function setNotRevealedURI(string memory _notRevealedURI) public onlyOwner {
        notRevealedUri = _notRevealedURI;
    }

    function setBaseURI(string memory _newBaseURI) public onlyOwner {
        baseURI = _newBaseURI;
    }

    function flipSaleActive() public onlyOwner {
        _isSaleActive = !_isSaleActive;
    }

    function flipReveal() public onlyOwner {
        _revealed = !_revealed;
    }

    function mintableAmount(address _address) public view returns (uint256) {
        return MAX_MINT_PER_USER - mintedAmount[_address];
    }

    function whiteListMint(
        uint256 _amount,
        bytes32[] calldata proof
    ) external payable {
        require(_isSaleActive, "Sale is not active");
        require(_verifyProof(proof, merkleRoot), "Invalid merkle proof");
        require(
            mintedAmount[msg.sender] + _amount <= MAX_MINT_PER_USER,
            "Exceeds max mint per user"
        );
        require(totalSupply() + _amount < MAX_SUPPLY, "Exceeds max supply");
        require(msg.value == mintPrice * _amount, "Incorrect ETH amount");

        mintedAmount[msg.sender] += _amount;

        for (uint256 i = 0; i < _amount; i++) {
            uint256 tokenId = _tokenIdCounter.current();
            _tokenIdCounter.increment();
            _safeMint(msg.sender, tokenId);
        }
    }

    function safeMint(address _to, uint256 _amount) public onlyOwner {
        require(totalSupply() + _amount < MAX_SUPPLY, "Exceeds max supply");
        for (uint256 i = 0; i < _amount; i++) {
            uint256 tokenId = _tokenIdCounter.current();
            _tokenIdCounter.increment();
            _safeMint(_to, tokenId);
        }
    }

    function tokenURI(
        uint256 tokenId
    ) public view virtual override returns (string memory) {
        require(
            _exists(tokenId),
            "ERC721Metadata: URI query for nonexistent token"
        );

        if (_revealed == false) {
            return notRevealedUri;
        }
        string memory base = _baseURI();
        return
            bytes(base).length > 0
                ? string(abi.encodePacked(base, tokenId.toString()))
                : "";
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return baseURI;
    }

    function withdraw(address to) public onlyOwner {
        uint256 balance = address(this).balance;
        payable(to).transfer(balance);
    }

    function _verifyProof(
        bytes32[] calldata proof,
        bytes32 root
    ) internal view returns (bool) {
        bytes32 leaf = keccak256(
            bytes.concat(keccak256(abi.encode(msg.sender)))
        );
        return MerkleProof.verify(proof, root, leaf);
    }
}

