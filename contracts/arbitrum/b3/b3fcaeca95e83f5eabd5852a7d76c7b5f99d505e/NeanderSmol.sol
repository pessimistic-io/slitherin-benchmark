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

    IERC20 private magic;
    uint256 public magicPrice;
    mapping(address => uint256) private magicMinted;

    bool public treasuryMinted;
    address public treasury;

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
        publicPrice = 0.02 ether;
        revealed = true;
        treasuryMinted = false;
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721EnumerableUpgradeable, AccessControlUpgradeable) returns (bool) {
        return ERC721EnumerableUpgradeable.supportsInterface(interfaceId) || AccessControlUpgradeable.supportsInterface(interfaceId);
    }

    function publicMint(uint256 amount) external payable{
        require(msg.value >= publicPrice * amount, "Incorrect Price");
        require(publicActive, "Public not active");
        require(_tokenIdTracker.current() < TOTAL_SUPPLY, "5678 Max Supply");
        require(publicMinted[msg.sender] + amount <= 30, "Mints exceeded");
        publicMinted[msg.sender] += amount;

        for(uint256 i=0; i<amount; i++) {
            _mint(msg.sender);
        }
    }

    function magicMint(uint256 amount) external {
        require(magic.balanceOf(msg.sender) >= magicPrice * amount, "Not enough balance");
        require(publicActive, "Public not active");
        require(_tokenIdTracker.current() < TOTAL_SUPPLY, "5678 Max Supply");
        require(magicMinted[msg.sender] + amount <= 30, "Mints exceeded");
        magicMinted[msg.sender] += amount;

        magic.transferFrom(msg.sender, address(this), magicPrice * amount);
        for(uint256 i=0; i<amount; i++) {
            _mint(msg.sender);
        }
    }

    function _mint(address _to) internal {
        uint256 _tokenId = _tokenIdTracker.current();
        _tokenIdTracker.increment();
        require(_tokenId <= TOTAL_SUPPLY, "Exceeded supply");
        
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

    function setPublicPrice(uint256 amount) external onlyAdmin {
        publicPrice = amount;
    }

    function setMagic(address _magic) external onlyAdmin {
        magic = IERC20(_magic);
    }

    function setMagicPrice(uint256 price) external onlyAdmin {
        magicPrice = price;
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        return bytes(baseURI).length > 0 ? string(abi.encodePacked(baseURI, tokenId.toString())) : "";
    }

    function withdrawAll() external onlyOwner {
        require(payable(msg.sender).send(address(this).balance));
        require(magic.transfer(msg.sender, magic.balanceOf(address(this))));
    }

    function treasuryMint(uint256 amount) external onlyAdmin{
        require(!treasuryMinted, "Treasury has already minted!");
        require(msg.sender == treasury);

        for(uint256 i=0; i<amount; i++) {
            _mint(msg.sender);
        }
    }

    function setTreasury(address _treasury) external onlyAdmin{
        treasury = _treasury;
    }
}

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}
