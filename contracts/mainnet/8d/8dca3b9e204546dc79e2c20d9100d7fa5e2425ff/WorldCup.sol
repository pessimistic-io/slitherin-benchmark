// SPDX-License-Identifier: MIT
pragma solidity >=0.4.25 <0.9.0;

import "./ERC721A.sol";
import "./Ownable.sol";
import "./ERC2981.sol";
import "./ReentrancyGuard.sol";
import "./MerkleProof.sol";
import "./DefaultOperatorFilterer.sol";

contract WorldCup is
    ERC721A,
    ERC2981,
    Ownable,
    DefaultOperatorFilterer,
    ReentrancyGuard
{

    string private _baseUri;
    bytes32 private whitelistMerkleRoot;
    uint96 private _royaltyPercent = 1000;
    uint256 private maxMintPerWallet = 5;
    uint256 private maxWhitelistMintPerWallet = 1;
    uint256 private maxSupply = 2022;
    uint256 public mintStartTime = 1668863700;
    uint256 public price = 0.02022 ether;

    mapping(address => uint256) private whitelistMintCount;

    constructor() ERC721A("World Cup", "WORLDCUP") {
        _setDefaultRoyalty(address(msg.sender), _royaltyPercent);
    }

    function publicCheckWhitelist(bytes32[] calldata proof, address sender)
        external
        view
        returns (bool)
    {
        return verifyWhitelist(proof, sender);
    }

    function verifyWhitelist(bytes32[] calldata proof, address sender)
        private
        view
        returns (bool)
    {
        return
            MerkleProof.verify(
                proof,
                whitelistMerkleRoot,
                keccak256(abi.encodePacked(sender))
            );
    }

    function mint(uint256 _count, bytes32[] calldata _proof)
        public
        payable
        nonReentrant
    {
        require(block.timestamp >= mintStartTime, "Mint Not Open Yet");
        require(_count > 0, "Mint at least 1");
        require(
            balanceOf(msg.sender) + _count <= maxMintPerWallet,
            "Max mint reached"
        );
        require(totalSupply() + _count <= maxSupply, "NFT supply not enough");

        uint256 totalPrice = _count * price;
        // check if minter is whitelisted, and first time mint
        bool isWhiteList = verifyWhitelist(_proof, msg.sender);
        if (isWhiteList && whitelistMintCount[msg.sender] == 0) {
            totalPrice -= price;
        }

        require(msg.value >= totalPrice, "ether amount not correct");

        _safeMint(msg.sender, _count);

        if (isWhiteList && whitelistMintCount[msg.sender] == 0) {
            whitelistMintCount[msg.sender] += _count;
        }

    }

    function setMaxSupply(uint256 _maxSupply) external onlyOwner {
        maxSupply = _maxSupply;
    }

    function isWhitelistMinted() external view returns (bool) {
        return whitelistMintCount[msg.sender] > 0;
    }

    function setWhitelistMerkleRoot(bytes32 _root) external onlyOwner {
        whitelistMerkleRoot = _root;
    }

    function setMintStartTime(uint256 _startTime) external onlyOwner {
        mintStartTime = _startTime;
    }

    function withdrawPartial() external payable onlyOwner {
        require(payable(msg.sender).send((address(this).balance * 3) / 10));
    }

    function withdrawBalance() external payable onlyOwner {
        require(payable(msg.sender).send(address(this).balance));
    }

    function setPrice(uint256 _newPrice) external onlyOwner {
        price = _newPrice;
    }

    function reveal(string memory _revealBaseURI) external onlyOwner {
        _baseUri = _revealBaseURI;
    }

    function getNFTBalance(address _nftOwner)
        external
        view
        returns (uint256 result)
    {
        return balanceOf(_nftOwner);
    }

    // internal
    function _baseURI() internal view override returns (string memory) {
        return _baseUri;
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721A, ERC2981)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public payable override onlyAllowedOperator(from) {
        super.transferFrom(from, to, tokenId);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public payable override onlyAllowedOperator(from) {
        super.safeTransferFrom(from, to, tokenId);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) public payable override onlyAllowedOperator(from) {
        super.safeTransferFrom(from, to, tokenId, data);
    }
}

