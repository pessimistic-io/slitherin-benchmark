//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.18;

import {IPolis} from "./IPolis.sol";
import {ERC721AQueryable, ERC721A} from "./ERC721AQueryable.sol";
import {IERC721A} from "./IERC721A.sol";
import {IAccessControlHolder, IAccessControl} from "./IAccessControlHolder.sol";
import {IERC2981, ERC2981} from "./ERC2981.sol";
import {Ownable} from "./Ownable.sol";

contract Polis is
    IPolis,
    IAccessControlHolder,
    ERC721AQueryable,
    ERC2981,
    Ownable
{
    bytes32 internal constant POLIS_MINTER = keccak256("POLIS_MINTER");
    bytes32 internal constant POLIS_UPGRADE = keccak256("POLIS_UPGRADE");
    bytes32 internal constant METADATA_MANAGER = keccak256("METADATA_MANAGER");

    IAccessControl public immutable override acl;
    string internal baseTokenURI;
    string public override contractURI;
    mapping(uint256 => uint8) internal senateLevels_;
    mapping(address => bool) public freePolisMinted;

    modifier onlyMinterRoleAccess() {
        _ensureHasMinterRole(msg.sender);
        _;
    }

    modifier onlyUpgradeRoleAccess() {
        _ensureHasUpgradeRole(msg.sender);
        _;
    }

    modifier canMintFreeToken() {
        _ensureCanMint(msg.sender);
        _;
    }

    modifier onlyIfExsits(uint256 tokenId) {
        _ensureExists(tokenId);
        _;
    }

    modifier onlyMetadataManager() {
        _ensureHasMetadataManagerRole(msg.sender);
        _;
    }

    constructor(
        IAccessControl acl_,
        uint96 royaltyNumerator_,
        address owner_,
        address treasury_,
        string memory baseTokenURI_,
        string memory contractURI_
    ) ERC721A("SpartaDex - Polis", "POLIS") {
        acl = acl_;
        baseTokenURI = baseTokenURI_;
        contractURI = contractURI_;
        _setDefaultRoyalty(treasury_, royaltyNumerator_);
        _transferOwnership(owner_);
    }

    function upgrade(
        uint256 tokenId,
        uint8 level
    ) external onlyUpgradeRoleAccess onlyIfExsits(tokenId) {
        _upgrade(tokenId, level);
    }

    function mintAsMinter(address to) external override onlyMinterRoleAccess {
        _safeMint(to, 1);
    }

    function mint() external canMintFreeToken {
        address sender = msg.sender;
        _safeMint(sender, 1);
        freePolisMinted[sender] = true;
    }

    function setBaseTokenURI(
        string calldata baseTokenURI_
    ) external override onlyMetadataManager {
        string memory previousBaseTokenURI = baseTokenURI;
        baseTokenURI = baseTokenURI_;

        emit BaseTokenURIChanged(previousBaseTokenURI, baseTokenURI);
    }

    function setContractURI(
        string calldata contractURI_
    ) external override onlyMetadataManager {
        string memory previousContractURI = contractURI;
        contractURI = contractURI_;

        emit ContractURIChanged(previousContractURI, contractURI);
    }

    function boost(
        uint256 tokenId,
        uint256 from
    ) external view returns (uint256) {
        uint256 level = senateLevels_[tokenId];

        uint256 boostFactor;

        if (level <= 10) {
            boostFactor = 100 + (level * 2);
        } else if (level <= 20) {
            boostFactor = 120 + ((level - 10) * 5);
        } else if (level <= 30) {
            boostFactor = 170 + ((level - 20) * 8);
        } else if (level <= 40) {
            boostFactor = 250 + ((level - 30) * 12);
        } else {
            boostFactor = 370 + ((level - 40) * 15);
        }

        uint256 boostedValue = (from * boostFactor) / 100;

        return boostedValue;
    }

    function senateLevel(uint256 tokenId) external view returns (uint8) {
        return senateLevels_[tokenId];
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(IERC721A, ERC721A, ERC2981) returns (bool) {
        return
            ERC721A.supportsInterface(interfaceId) ||
            ERC2981.supportsInterface(interfaceId);
    }

    function ownerOf(
        uint256 tokenId
    ) public view override(ERC721A, IERC721A, IPolis) returns (address) {
        return ERC721A.ownerOf(tokenId);
    }

    function _upgrade(uint256 tokenId, uint8 level) internal {
        uint8 currentLevel = senateLevels_[tokenId];
        if (currentLevel >= level) {
            revert LevelDowngrade();
        }
        senateLevels_[tokenId] = level;
        emit Upgrade(tokenId, level);
    }

    function _ensureHasMinterRole(address addr) internal view {
        if (!acl.hasRole(POLIS_MINTER, addr)) {
            revert OnlyMinterRoleAccess();
        }
    }

    function _ensureHasUpgradeRole(address addr) internal view {
        if (!acl.hasRole(POLIS_UPGRADE, addr)) {
            revert OnlyUpgradeRoleAccess();
        }
    }

    function _ensureExists(uint256 tokenId) internal view {
        if (!_exists(tokenId)) {
            _revert(URIQueryForNonexistentToken.selector);
        }
    }

    function _startTokenId() internal view virtual override returns (uint256) {
        return 1;
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return baseTokenURI;
    }

    function _ensureCanMint(address sender) internal view {
        if (freePolisMinted[sender]) {
            revert CannotMintFreePolis();
        }
    }

    function _ensureHasMetadataManagerRole(address sender) internal view {
        if (!acl.hasRole(METADATA_MANAGER, sender)) {
            revert OnlyMetadataManagerAccess();
        }
    }
}

