// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./ERC721.sol";
import "./Ownable.sol";
import "./Strings.sol";
import "./ERC2981.sol";
import { DefaultOperatorFilterer } from "./DefaultOperatorFilterer.sol";

contract PlanetMan is ERC721, Ownable, ERC2981, DefaultOperatorFilterer {

    constructor(
        string memory _baseURI,
        address receiver, /* Royalty receiver address of MetaX */
        uint96 feeNumerator /* Declare % of royalty */
    ) ERC721("PlanetMan", "PlanetMan") {
        tokenIdByRarity[0] = 7000; /* Common NFT tokenId from #7001~#10000 */
        tokenIdByRarity[1] = 2000; /* Uncommon NFT tokenId from #2001~#7000 */
        tokenIdByRarity[2] = 500; /* Rare NFT tokenId from #501~#2000 */
        tokenIdByRarity[3] = 50; /* Epic NFT tokenId from #51~#500 */
        tokenIdByRarity[4] = 0; /* Legendary NFT tokenId from #1~#50 */
        baseURI = _baseURI;
        _setDefaultRoyalty(receiver, feeNumerator); /* Initialize royalty setting */
    }

/** Metadata of PlanetMan **/
    bool public Frozen; /* Freeze metadata if true */

    function setFrozen () public onlyOwner {
        Frozen = true; /* Once frozen cannot be unfrozen */
    }

    string public baseURI; /* Metadata storing in IPFS */

    function setBaseURI(string memory newBaseURI) public onlyOwner {
        require(!Frozen, "PlanetMan: Metadata is frozen.");
        baseURI = newBaseURI;
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_exists(tokenId), "PlanetMan: Token not exist.");
        return bytes(baseURI).length > 0 ? string(abi.encodePacked(baseURI, Strings.toString(tokenId), ".json")) : "";
    }

/** Mint **/
    /* Status */
    bool public Open; /* Set the status of PlanetMan minting */

    function setOpen(bool _Open) public onlyOwner {
        Open = _Open;
    }

    /* Quantity */
    uint256 public immutable Max = 10000; /* Max supply of PlanetMan is 10000 */

    uint256 public totalSupply; /* Total quantity of PlanetMan minted */

    uint256[] public maxRarity = [3000, 5000, 1500, 450, 50]; /* Max supply of each rarity | #0=>Common=>3000 | #1=>Uncommon=>5000 | #2=>Rare=>1500 | #3=>Epic=>450 | #4=>Legendary=>50 */

    mapping (uint256 => uint256) public numberMinted; /* Quantity minted for each rarity */

    /* Price */
    uint256[] public Price = [0 ether, 0.02 ether, 0.08 ether, 0.2 ether, 0.5 ether]; /* Price of each rarity | #0=>Common=>free | #1=>Uncommon=>0.02eth | #2=>Rare=>0.08eth | #3=>Epic=>0.2eth | #4=>Legendary=>0.5eth */

    /* Rarity */
    mapping (uint256 => uint256) public rarity; /* mapping tokenId => rarity */

    function getRarity(uint256 _tokenId) external view returns (uint256) {
        require(_exists(_tokenId), "PlanetMan: Token not exist.");
        return rarity[_tokenId]; /* Return rarity of PlanetMan for external verification */
    }

    /* Mint Limit */
    mapping (uint256 => uint256) public tokenIdByRarity; /* Track minting progress of each rarity */

    mapping (address => mapping(uint256 => bool)) public alreadyMinted; /* Each wallet can only mint one PlanetMan of certain rarity */

    event mintRecord(address owner, uint256 tokenId, uint256 time);

    /* Public Mint */
    function Mint(address owner, uint256 _rarity) public payable {
        require(Open, "PlanetMan: Mint is closed.");
        require(tx.origin == msg.sender, "PlanetMan: Contract not allowed.");
        require(_rarity < 5, "PlanetMan: Incorrect rarity inputs.");
        require(totalSupply < Max, "PlanetMan: Exceed the max supply.");
        require(numberMinted[_rarity] < maxRarity[_rarity], "PlanetMan: Exceed the public mint limit of that rarity.");
        require(!alreadyMinted[owner][_rarity], "PlanetMan: Limit 1 per rarity.");
        require(msg.value >= Price[_rarity], "PlanetMan: Not enough payment.");
        
        tokenIdByRarity[_rarity] ++;
        uint256 tokenId = tokenIdByRarity[_rarity];

        _safeMint(owner, tokenId);

        numberMinted[_rarity] ++;
        totalSupply ++;
        rarity[tokenId] = _rarity;
        alreadyMinted[owner][_rarity] = true;

        emit mintRecord(owner, tokenId, block.timestamp);
    }

    /* Airdrop Mint */
    function Airdrop(address[] memory owner, uint256[] memory _rarity) public onlyOwner {
        require(Open, "PlanetMan: Mint is close.");
        require(owner.length == _rarity.length, "PlanetMan: Incorrect inputs.");
        for (uint256 i=0; i<owner.length; i++) {
            require(totalSupply < Max, "PlanetMan: Exceed the max supply.");
            require(numberMinted[_rarity[i]] < maxRarity[_rarity[i]], "PlanetMan: Exceed the mint limit of that rarity.");
            require(_rarity[i] < 5, "PlanetMan: Incorrect rarity inputs.");
            
            tokenIdByRarity[_rarity[i]] ++;
            uint256 tokenId = tokenIdByRarity[_rarity[i]];

            _safeMint(owner[i], tokenId);

            numberMinted[_rarity[i]] ++;
            totalSupply ++;
            rarity[tokenId] = _rarity[i];

            emit mintRecord(owner[i], tokenId, block.timestamp);
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

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721, ERC2981) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

/** Withdraw **/
    function Withdraw (address recipient) public onlyOwner {
        payable(recipient).transfer(address(this).balance);
    }
}
