// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.2;

import "./ERC721EnumerableUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./CountersUpgradeable.sol";
import "./ERC721Upgradeable.sol";
import "./SafeMathUpgradeable.sol";

contract ModContract is ERC721EnumerableUpgradeable, OwnableUpgradeable {
    using SafeMathUpgradeable for uint256;
    using AddressUpgradeable for address;
    using CountersUpgradeable for CountersUpgradeable.Counter;
    mapping(address => bool) private adminAccess;

    CountersUpgradeable.Counter private _tokenIdCounter;
    mapping(uint256 => Mod) private mods;

    struct Mod {
        uint256 modId;
        uint256 item;
        uint256 mountType;
    }

    function initialize() public initializer {
        __ERC721Enumerable_init();
        __ERC721_init("Mod", "Mod");
        __Ownable_init();
    }

    function setAdminAccess(address user, bool access) external onlyOwner {
        adminAccess[user] = access;
    }

    function mintMod(address receiver, Mod memory mod) external onlyAdminAccess returns (uint256) {
        uint256 nextTokenId = _getNextTokenId();
        _mint(receiver, nextTokenId);
        mod.modId = nextTokenId;
        mods[nextTokenId] = mod;
        return nextTokenId;
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

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override(ERC721EnumerableUpgradeable) {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721EnumerableUpgradeable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}

