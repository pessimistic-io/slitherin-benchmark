// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "./ERC721.sol";
import "./ERC721Enumerable.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./Counters.sol";
import "./Pausable.sol";
import "./MerkleProof.sol";

contract test is ERC721, ERC721Enumerable, Pausable, Ownable, ReentrancyGuard{ 
    using Strings for uint256;
    using Counters for Counters.Counter;
    using MerkleProof for bytes32[];

    enum Stage {
        Init,
        Airdrop,
        Whitelist,
        TeamMint,
        PublicSale
    }

    Counters.Counter private _tokenIdCounter;
    
    bytes32 public merkleRoot;
    string public provenanceHash;
    string public baseURI = "";
    string public baseExtension = ".json";
    uint256 public maxMintPerTx;     
    bool public tokenURIFrozen = false;
    bool public provenanceHashFrozen = false;

    address public withdrawlAddress = 0x12B58f5331a6DC897932AA7FB5101667ACdf03e2;

    // ~ Sale stages ~
    // stage 0: Init
    // stage 1: Airdrop
    // stage 2: Whitelist
    // stage 3: Team Mint 
    // stage 4: Public Sale

    // Whitelist mint (stage=2)
    uint256 public whitelistSupply;                       
    mapping(address => bool) public claimed;              
    
    // Team Mint (stage=3)
    uint256 public teamMintSupply;                          
    uint256 public teamMintCount;

    // Public Sale (stage=4)
    uint256 public totalSaleSupply;         
    uint256 public salePrice = 0.1 ether;  

    Stage public stage;

    constructor(
        string memory _name,
        string memory _symbol,
        string memory _baseURI,
        uint256 _whitelistSupply,
        uint256 _teamMintSupply,
        uint256 _totalSaleSupply,
        uint256 _maxMintPerTx

    )   ERC721(_name, _symbol) {
        whitelistSupply = _whitelistSupply;
        teamMintSupply = _teamMintSupply;
        totalSaleSupply = _totalSaleSupply;
        maxMintPerTx = _maxMintPerTx;
        baseURI = _baseURI;
        _tokenIdCounter.increment();
    }

    // Stage 1 - Airdrop
    function airdropTest(
        uint8 mintAmount, 
        address to
    ) 
        external
        onlyOwner 
    {
        require(stage > Stage.Init, "No airdrops at init.");
        require(totalSupply()  + mintAmount <= totalSaleSupply, "Mint amount will exceed total sale supply.");
        for (uint256 i = 1; i <= mintAmount; i++) {
            _safeMint(to, _tokenIdCounter.current());
            _tokenIdCounter.increment();
        }
    }

    // Stage 2 - Whitelist Sale
    function whitelistMint(
        bytes32[] calldata merkleProof
    ) 
        external
        payable 
        nonReentrant 
        whenNotPaused 
    {
        require(stage == Stage.Whitelist, "Whitelist sale not initiated.");
        require(salePrice == msg.value, "Incorrect ETH value sent.");
        require(merkleProof.verify(merkleRoot, keccak256(abi.encodePacked(msg.sender))), "Address not on whitelist.");
        require(claimed[msg.sender] == false, "Whitelist mint already claimed."); 
        require(totalSupply() + 1 <= totalSaleSupply, "Transaction exceeds total sale supply.");  
        claimed[msg.sender] = true;
        _safeMint(msg.sender, _tokenIdCounter.current());
        _tokenIdCounter.increment();
    }

    // Stage 3 - Team Mint
    function teamMint(
        uint8 mintAmount
    ) 
        external 
        onlyOwner 
    {
        require(stage == Stage.TeamMint, "Team mint not initiated.");
        require(mintAmount > 0, "Mint amount must be greater than 0.");
        require(mintAmount + teamMintCount <= teamMintSupply, "Transaction exceeds total team sale supply.");   
        require(totalSupply()  + mintAmount <= totalSaleSupply, "Transaction exceeds total sale supply.");  
        teamMintCount += mintAmount;
        for (uint256 i = 1; i <= mintAmount; i++) {
            _safeMint(msg.sender, _tokenIdCounter.current());
            _tokenIdCounter.increment();
        }
    }

    // Stage 4 - Public Mint
    function publicMint(
        uint256 mintAmount
    ) 
        external
        payable 
        nonReentrant 
        whenNotPaused  
    {
        require(stage == Stage.PublicSale, "Public Sale not initiated.");
        require(salePrice * mintAmount == msg.value, "Incorrect ETH value sent.");
        require(mintAmount > 0, "Mint amount must be greater than 0.");
        require(totalSupply()  + mintAmount <= totalSaleSupply, "Transaction exceeds total sale supply.");
        require(mintAmount <= maxMintPerTx, "Exceeds max allowed mints per transaction.");  
        for (uint256 i = 1; i <= mintAmount; i++) {
            _safeMint(msg.sender, _tokenIdCounter.current());
            _tokenIdCounter.increment();
        }
    }

    //Owner functions
    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // to be used in case of manual override
    function setClaim(address wlAddress) external onlyOwner{
        claimed[wlAddress] = true;
    }

    // to be used in case of WL error
    function undoClaim(address wlAddress) external onlyOwner{
        claimed[wlAddress] = false;
    }

    function setMerkleRoot(bytes32 _merkleRoot) external onlyOwner {
        merkleRoot = _merkleRoot;
    }

    function setBaseURI(string memory _newBaseURI) external onlyOwner {
        require(!tokenURIFrozen, "BaseURI is frozen.");
        baseURI = _newBaseURI;
    } 
    
    function freezeBaseURI() external onlyOwner {
        require(bytes(baseURI).length > 0, "BaseURI cannot be empty.");
        require(!tokenURIFrozen, "BaseURI is already frozen.");
        tokenURIFrozen = true;
    }

    function setBaseExtension(string memory _newBaseExtension) external onlyOwner {
        baseExtension = _newBaseExtension;
    }

    function setProvenanceHash(string memory _provenanceHash) external onlyOwner {
        require(bytes(_provenanceHash).length > 0, "Provenance hash cannot be empty string.");
        require(!provenanceHashFrozen, "Provenance hash is frozen.");
        provenanceHash = _provenanceHash;
    }

    function freezeProvenanceHash() external onlyOwner {
        require(bytes(provenanceHash).length > 0, "Provenance hash is not set.");
        require(!provenanceHashFrozen, "Provenance hash is already frozen.");
        provenanceHashFrozen = true;
    }

    function setWithdrawlAddress(address _withdrawlAddress) external onlyOwner {
        withdrawlAddress = _withdrawlAddress;
    }

    function setSalePrice(uint256 _salePrice) external onlyOwner {
        salePrice = _salePrice;
    }

    function setMaxMintPerTx(uint256 _maxMintPerTx) external onlyOwner {
        maxMintPerTx = _maxMintPerTx;
    }

    function withdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No balance to withdraw.");
        (bool success, ) = payable(withdrawlAddress).call{value: balance}("");
        require(success, "Failed to withdraw balance.");
    }

    function setStage(Stage _stage) external onlyOwner {
        require(provenanceHashFrozen == true, "Provenance hash must be frozen before minting can start.");
        require(merkleRoot != 0, "Merkle root must be set beefore minting can start.");
        stage = _stage;
    }

    // External view functions
    function lastMintAddress() external view returns (address){
        return ownerOf(totalSupply());
    }

    function lastMintID() external view returns (uint256){
        return(totalSupply());
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token.");
        return string(abi.encodePacked(baseURI, tokenId.toString(), baseExtension));
    }

    function getTokensLeft() external view returns (uint256) {
        return totalSaleSupply - totalSupply();
    }
    
    function walletOfOwner(address owner) external view returns (uint256[] memory) {
        uint256 ownerTokenCount = balanceOf(owner);
        uint256[] memory tokensIds = new uint256[](ownerTokenCount);
        for (uint256 i; i < ownerTokenCount; i++) {
            tokensIds[i] = tokenOfOwnerByIndex(owner, i);
        }
        return tokensIds;
    }

    function verify(address account, bytes32[] calldata merkleProof) external view returns (bool) {
        if (merkleProof.verify(merkleRoot, keccak256(abi.encodePacked(account)))) {
            return true;
        }
        return false;
    }
    
    function _beforeTokenTransfer(address from, address to, uint256 tokenId) internal whenNotPaused override(ERC721, ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    // The following functions are overrides required by Solidity.

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC721Enumerable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

}
