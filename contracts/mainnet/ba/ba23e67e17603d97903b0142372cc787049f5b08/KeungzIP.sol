// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

// import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "./IERC721.sol";
// import "@openzeppelin/contracts/utils/Strings.sol";
import "./Erc721LockRegistryDummy.sol";
import "./IERC721xHelper.sol";

contract KeungzIP is
    ERC721xDummy,
    IERC721xHelper
{
    uint256 public MAX_SUPPLY;

    string public baseTokenURI;
    string public tokenURISuffix;
    string public tokenURIOverride;

    IERC721 public kzgContract;

    mapping(address => mapping(address => bool)) public isClaiming; // owner => operator => bool

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address kzgAddr) public initializer {
        ERC721xDummy.__ERC721x_init("Keungz IP", "KzIP");
        kzgContract = IERC721(kzgAddr);
        MAX_SUPPLY = 432;
    }
    
    function setKZGContract(address _addr) external onlyOwner {
        kzgContract = IERC721(_addr);
    }
    
    function airdrop(address receiver, uint256 tokenAmount) external onlyOwner {
        safeMint(receiver, tokenAmount);
    }

    function safeMint(address receiver, uint256 quantity) internal {
        require(_totalMinted() + quantity <= MAX_SUPPLY, "exceed MAX_SUPPLY");
        _mint(receiver, quantity);
    }

    function isApprovedForAll(address owner, address operator) public view virtual override(ERC721AUpgradeable, IERC721AUpgradeable) returns (bool) {
        if (isClaiming[owner][operator]) return true;
        return super.isApprovedForAll(owner, operator);
    }

    function claim(uint256 tokenId) external {
        require(kzgContract.ownerOf(tokenId) == msg.sender, "Not KzG owner");
        address curOwner = ownerOf(tokenId);
        require(curOwner != msg.sender, "Already owning Keungz IP");
        isClaiming[curOwner][msg.sender] = true;
        super.transferFrom(curOwner, msg.sender, tokenId);
        isClaiming[curOwner][msg.sender] = false;
    }

    function approve(address to, uint256 tokenId)
        public
        override(ERC721AUpgradeable, IERC721AUpgradeable)
    {
        require(false, "Approve not open");
    }

    function setApprovalForAll(address operator, bool approved)
        public
        override(ERC721AUpgradeable, IERC721AUpgradeable)
    {
        require(false, "Approve not open");
    }

    function transferFrom(
        address _from,
        address _to,
        uint256 _tokenId
    ) public virtual override(ERC721AUpgradeable, IERC721AUpgradeable) {
        require(false, "Transfer not open");
    }

    function safeTransferFrom(
        address _from,
        address _to,
        uint256 _tokenId,
        bytes memory data
    ) public virtual override(ERC721AUpgradeable, IERC721AUpgradeable) {
        require(false, "Transfer not open");
    }

    function compareStrings(string memory a, string memory b)
        public
        pure
        returns (bool)
    {
        return keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b));
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return baseTokenURI;
    }

    function tokenURI(uint256 _tokenId)
        public
        view
        override(ERC721AUpgradeable, IERC721AUpgradeable)
        returns (string memory)
    {
        if (bytes(tokenURIOverride).length > 0) {
            return tokenURIOverride;
        }
        return string.concat(super.tokenURI(_tokenId), tokenURISuffix);
    }

    function setBaseURI(string calldata baseURI) external onlyOwner {
        baseTokenURI = baseURI;
    }

    function setTokenURISuffix(string calldata _tokenURISuffix)
        external
        onlyOwner
    {
        if (compareStrings(_tokenURISuffix, "!empty!")) {
            tokenURISuffix = "";
        } else {
            tokenURISuffix = _tokenURISuffix;
        }
    }

    function setTokenURIOverride(string calldata _tokenURIOverride)
        external
        onlyOwner
    {
        if (compareStrings(_tokenURIOverride, "!empty!")) {
            tokenURIOverride = "";
        } else {
            tokenURIOverride = _tokenURIOverride;
        }
    }

    // =============== IERC721xHelper ===============
    function isUnlockedMultiple(uint256[] calldata tokenIds)
        external
        view
        returns (bool[] memory)
    {
        bool[] memory part = new bool[](tokenIds.length);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            part[i] = true;
        }
        return part;
    }

    function ownerOfMultiple(uint256[] calldata tokenIds)
        external
        view
        returns (address[] memory)
    {
        address[] memory part = new address[](tokenIds.length);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            part[i] = ownerOf(tokenIds[i]);
        }
        return part;
    }

    function tokenNameByIndexMultiple(uint256[] calldata tokenIds)
        external
        view
        returns (string[] memory)
    {
        string[] memory part = new string[](tokenIds.length);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            part[i] = "Keungz IP";
        }
        return part;
    }
}

