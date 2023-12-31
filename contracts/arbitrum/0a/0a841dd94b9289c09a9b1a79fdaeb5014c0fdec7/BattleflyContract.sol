// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.2;

import "./ERC721EnumerableUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./CountersUpgradeable.sol";
import "./ERC721Upgradeable.sol";
import "./SafeMathUpgradeable.sol";

contract BattleflyContract is ERC721EnumerableUpgradeable, OwnableUpgradeable {
    using SafeMathUpgradeable for uint256;
    using AddressUpgradeable for address;
    using CountersUpgradeable for CountersUpgradeable.Counter;
    using StringsUpgradeable for uint256;

    mapping(address => bool) private adminAccess;
    mapping(uint256 => uint256) private battleflyTypes;

    CountersUpgradeable.Counter private _tokenIdCounter;
    event SetAdminAccess(address indexed user, bool access);

    function initialize() public initializer {
        __ERC721Enumerable_init();
        __ERC721_init("Battlefly", "Battlefly");
        __Ownable_init();
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token");
        return string(abi.encodePacked("https://api.battlefly.game/battleflies/", tokenId.toString(), "/metadata"));
    }

    function setAdminAccess(address user, bool access) external onlyOwner {
        adminAccess[user] = access;
        emit SetAdminAccess(user, access);
    }

    function mintBattlefly(address receiver, uint256 battleflyType) external onlyAdminAccess returns (uint256) {
        uint256 nextTokenId = _getNextTokenId();
        battleflyTypes[nextTokenId] = battleflyType;
        _mint(receiver, nextTokenId);
        return nextTokenId;
    }

    function mintBattleflies(
        address receiver,
        uint256 _battleflyType,
        uint256 amount
    ) external onlyAdminAccess returns (uint256[] memory) {
        uint256[] memory tokenIds = new uint256[](amount);
        for (uint256 i = 0; i < amount; i++) {
            uint256 nextTokenId = _getNextTokenId();
            battleflyTypes[nextTokenId] = _battleflyType;
            tokenIds[i] = nextTokenId;
            _mint(receiver, nextTokenId);
        }
        return tokenIds;
    }

    function getBattleflyType(uint256 tokenId) external view returns (uint256) {
        return battleflyTypes[tokenId];
    }

    function _getNextTokenId() private view returns (uint256) {
        return (_tokenIdCounter.current() + 1);
    }

    function _mint(address to, uint256 tokenId) internal override(ERC721Upgradeable) {
        super._mint(to, tokenId);
        _tokenIdCounter.increment();
    }

    modifier onlyAdminAccess() {
        require(adminAccess[_msgSender()] == true || _msgSender() == owner(), "Require admin access");
        _;
    }
}

