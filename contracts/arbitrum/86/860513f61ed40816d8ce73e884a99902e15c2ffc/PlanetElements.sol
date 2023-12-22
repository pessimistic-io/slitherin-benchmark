// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./ERC721.sol";
import "./AccessControl.sol";
import "./Ownable.sol";
import "./MerkleProof.sol";
import "./ERC2981.sol";
import { DefaultOperatorFilterer } from "./DefaultOperatorFilterer.sol";

contract PlanetElements is ERC721, AccessControl, Ownable, ERC2981, DefaultOperatorFilterer {

/** Roles **/
    bytes32 public constant Admin = keccak256("Admin");

    constructor(
        address receiver,
        uint96 feeNumerator
    ) ERC721 ("PlanetElements", "PlanetElements") {
        _setDefaultRoyalty(receiver, feeNumerator);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(Admin, msg.sender);
    }

/** Metadata **/
    mapping (uint256 => uint256) public tokenSeries; /* tokenId => Series */

    string[] public baseURI;

    function setBaseURI(string memory newBaseURI) public onlyRole(Admin) {
        for (uint256 i=0; i<baseURI.length; i++) {
            if (keccak256(abi.encodePacked(baseURI[i])) == keccak256(abi.encodePacked(newBaseURI))) {
                baseURI[i] = newBaseURI;
                break;
            } else {
                baseURI.push(newBaseURI);
            }
        }
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_exists(tokenId), "PlanetElements: Token not exist.");
        uint256 _series = tokenSeries[tokenId];
        return baseURI[_series];
    }

/** Whitelist **/
    bytes32 public merkleRoot;

    function setWhitelist(bytes32 _merkleRoot) public onlyRole(Admin) {
        merkleRoot = _merkleRoot;
    }

    function verify(uint256 _series, bytes32[] calldata merkleProof) public view returns (bool) {
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender, _series));
        return MerkleProof.verify(merkleProof, merkleRoot, leaf);
    }

/** Mint **/
    uint256 public _tokenId;

    function totalSupply() public view returns (uint256) {
        return _tokenId - numberBurnt;
    }

    uint256 public seriesMax;

    struct _Elements {
        uint256 Rarity;
        uint256 Limit;
        mapping (address => bool) alreadyMinted;
        uint256 startTime;
        uint256 endTime;
        uint256 totalMinted;
        bool WLRequired;
    }

    mapping (uint256 => _Elements) public Elements; /* Series => Info */

    function setElements(uint256 _series, uint256 _rarity, uint256 _limit, uint256 _startTime, uint256 _endTime) public onlyRole(Admin) {
        Elements[_series].Rarity = _rarity;
        Elements[_series].Limit = _limit;
        Elements[_series].startTime = _startTime;
        Elements[_series].endTime = _endTime;
        if (_series > seriesMax) {
            seriesMax = _series;
        }
    }

    function getRarity (uint256 tokenId) public view returns (uint256) {
        uint256 series = tokenSeries[tokenId];
        return Elements[series].Rarity;
    }

    function Mint(uint256 _series, bytes32[] calldata merkleProof) public {
        require(_series <= seriesMax, "PlanetElements: Series not exists.");
        require(!Elements[_series].alreadyMinted[msg.sender], "PlanetElements: Limited to 1 PlanetElements per series.");
        require(Elements[_series].totalMinted < Elements[_series].Limit, "PlanetElements: Over the limit of that series.");
        require(Elements[_series].startTime < block.timestamp, "PlanetElements: Mint of this series is not started.");
        require(Elements[_series].endTime > block.timestamp, "PlanetElements: Mint of this series is ended.");
        if (Elements[_series].WLRequired) {
            require(verify(_series, merkleProof), "PlanetElements: You are not in the whitelist.");
        }
        _tokenId++;
        _safeMint(msg.sender, _tokenId);
        tokenSeries[_tokenId] = _series;
        Elements[_series].alreadyMinted[msg.sender] = true;
        Elements[_series].totalMinted++;
    }

/** Burning **/
    uint256 public numberBurnt;

    function Burn (uint256 tokenId) public {
        require(ownerOf(tokenId) == msg.sender, "PlanetBadges: You are not the owner of this NFT.");
        _burn(tokenId);
        numberBurnt++;
    }

/** Binding Tokens With Wallet Address **/
    mapping (address => uint256[]) public wallet_token;

    function getAllTokens(address owner) public view returns (uint256[] memory) {
        return wallet_token[owner];
    }

    function addToken(address user, uint256 tokenId) internal {
        wallet_token[user].push(tokenId);
    }

    function removeToken(address user, uint256 tokenId) internal {
        uint256[] storage token = wallet_token[user];
        for (uint256 i=0; i<token.length; i++) {
            if(token[i] == tokenId) {
                token[i] = token[token.length - 1];
                token.pop();
                break;
            }
        }
    }

    function _beforeTokenTransfer(address from, address to, uint256 firstTokenId, uint256 batchSize) internal virtual override {
        super._beforeTokenTransfer(from, to, firstTokenId, batchSize);
        for (uint256 i=0; i<batchSize; i++) {
            uint256 tokenId = firstTokenId + i;
            if (from != address(0)) {
                removeToken(from, tokenId);
            }
            if (to != address(0)) {
                addToken(to, tokenId);
            }
        }
    }

/** Royalty **/
    function setRoyaltyInfo(address receiver, uint96 feeNumerator) external onlyOwner {
        _setDefaultRoyalty(receiver, feeNumerator);
    }

    function setTokenRoyalty(uint256 tokenId, address receiver, uint96 feeNumerator) external onlyOwner {
        _setTokenRoyalty(tokenId, receiver, feeNumerator);
    }

    function setApprovalForAll(address operator, bool approved) public override onlyAllowedOperatorApproval(operator) {
        super.setApprovalForAll(operator, approved);
    }

    function approve(address operator, uint256 tokenId) public override onlyAllowedOperatorApproval(operator) {
        super.approve(operator, tokenId);
    }

    function transferFrom(address from, address to, uint256 tokenId) public override onlyAllowedOperator(from) {
        super.transferFrom(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) public override onlyAllowedOperator(from) {
        super.safeTransferFrom(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data)
        public
        override
        onlyAllowedOperator(from)
    {
        super.safeTransferFrom(from, to, tokenId, data);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721, ERC2981, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

/** Withdraw **/
    function Withdraw(address recipient) public onlyOwner {
        payable(recipient).transfer(address(this).balance);
    }
}
