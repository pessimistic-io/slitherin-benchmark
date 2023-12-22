//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import "./ContractControl.sol";
import "./ERC721EnumerableUpgradeable.sol";
import "./MathUpgradeable.sol";
import "./StringsUpgradeable.sol";
import "./CountersUpgradeable.sol";
import "./MerkleProofUpgradeable.sol";

contract NeanderSmol is ContractControl, ERC721EnumerableUpgradeable {
    using StringsUpgradeable for uint256;
    using CountersUpgradeable for CountersUpgradeable.Counter;

    uint256 constant TOTAL_SUPPLY = 5678;

    CountersUpgradeable.Counter public _tokenIdTracker;

    string public baseURI;

    uint256 public decimals;
    uint256 public commonSenseMaxLevel;
    mapping(uint256 => uint256) public commonSense;

    bytes32 public merkleRoot;
    mapping(address => bool) private minted;
    mapping(address => uint256) private publicMinted;

    mapping(address => uint256) private multipleMints;
    mapping(address => uint256) private teamAddresses;

    bool public publicActive;
    bool public wlActive;

    uint256 public wlPrice;
    uint256 public publicPrice;

    bool private revealed;

    event SmolNeanderMint(
        address to, 
        uint256 tokenId 
    );

    event uriUpdate(
        string newURI
    );

    event commonSenseUpdated(
        uint256 tokenId,
        uint256 commonSense
    );

    function initialize() initializer public {
        __ERC721_init("Neander Smol", "NeanderSmol");
        ContractControl.initializeAccess();
        decimals = 9;
        commonSenseMaxLevel = 100 * (10**decimals);
        publicActive = false;
        wlActive = false;
        wlPrice = 0.01 ether;
        publicPrice = 0.03 ether;
        revealed = false;
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721EnumerableUpgradeable, AccessControlUpgradeable) returns (bool) {
        return ERC721EnumerableUpgradeable.supportsInterface(interfaceId) || AccessControlUpgradeable.supportsInterface(interfaceId);
    }

    function mint(bytes32[] calldata _merkleProof) external payable{
        require(wlActive, "SmolNeander: WL mint not active");
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender));
        require(MerkleProofUpgradeable.verify(_merkleProof, merkleRoot, leaf), "SmolNeander: Sender is not WL");
        require(minted[msg.sender] != true, "SmolNeander: Already minted");
        minted[msg.sender] = true;
        uint256 amount = 1;
        if(multipleMints[msg.sender] > 1) {
            amount = multipleMints[msg.sender];
        }
        require(msg.value >= amount * wlPrice, "SmolNeander: Incorrect Price");
        for(uint256 i=0; i<amount; i++) {
            _mint(msg.sender);
        }
    }

    function publicMint(uint256 amount) external payable{
        require(msg.value >= publicPrice * amount, "SmolNeander: Incorrect Price");
        require(publicActive, "SmolNeander: Public mint not active");
        require(publicMinted[msg.sender] + amount <= 2, "SmolNeander: Can only mint up to 2 from public sale");
        publicMinted[msg.sender] += amount;

        for(uint256 i=0; i<amount; i++) {
            _mint(msg.sender);
        }
    }

    function teamMint() external {
        require(publicActive || wlActive, "SmolNeander: Mint not active");
        require(teamAddresses[msg.sender] > 0, "SmolNeander: Not eligibe for team mint");

        for(uint256 i=0; i<teamAddresses[msg.sender]; i++) {
            _mint(msg.sender);
        }
    }

    function _mint(address _to) internal {
        uint256 _tokenId = _tokenIdTracker.current();
        _tokenIdTracker.increment();
        require(_tokenId <= TOTAL_SUPPLY, "SmolNeander: exceeded supply");
        
        emit SmolNeanderMint(_to, _tokenId);
        _safeMint(_to, _tokenId);
    }

    function updateCommonSense(uint256 _tokenId, uint256 amount) external onlyStakingContract {
        if(commonSense[_tokenId] + amount >= commonSenseMaxLevel) {
            commonSense[_tokenId] = commonSenseMaxLevel;
        } else{
            commonSense[_tokenId] += amount;
        }

        emit commonSenseUpdated(_tokenId, commonSense[_tokenId]);
    }

    function getCommonSense(uint256 _tokenId) external view returns (uint256) {
        return commonSense[_tokenId] / (10**decimals);
    }

    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    function setBaseURI(string memory newBaseURI) external onlyAdmin {
        baseURI = newBaseURI;
        emit uriUpdate(newBaseURI);
    }

    function setMerkleTree(bytes32 _merkleRoot) external onlyAdmin {
        merkleRoot = _merkleRoot;
    }

    function addTeam(address member, uint256 amount) external onlyAdmin {
        teamAddresses[member] = amount;
    }

    function removeTeam(address member) external onlyAdmin {
        teamAddresses[member] = 0;
    }

    function addMultiple(address member, uint256 amount) external onlyAdmin {
        multipleMints[member] = amount;
    }

    function removeMultiple(address member) external onlyAdmin {
        multipleMints[member] = 0;
    }

    function hasMultiple(address member) external view returns(uint256){
        return multipleMints[member];
    }

    function flipPublicState() external onlyAdmin {
        publicActive = !publicActive;
    }

    function flipWLState() external onlyAdmin {
        wlActive = !wlActive;
    }

    function flipRevealedState() external onlyAdmin {
        revealed = !revealed;
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        if(!revealed) {
            return bytes(baseURI).length > 0 ? string(abi.encodePacked(baseURI, tokenId.toString(), ".json")) : "";
        }
        else {
            uint256 commonSenseLevel = commonSense[tokenId] / (10**decimals);
            uint256 level = 0;
            if(commonSenseLevel >= 50 && commonSenseLevel < 100) level = 1;
            else if(commonSenseLevel >= 100) level = 2;
            return bytes(baseURI).length > 0 ? string(abi.encodePacked(baseURI, tokenId.toString(), "/", level.toString(), ".json")) : "";
        }
    }

    function withdrawAll() external onlyOwner {
        require(payable(msg.sender).send(address(this).balance));
    }
}
