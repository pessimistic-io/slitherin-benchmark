// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.2;

import "./ERC721EnumerableUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./CountersUpgradeable.sol";
import "./ERC721Upgradeable.sol";
import "./SafeMathUpgradeable.sol";
import "./EnumerableSetUpgradeable.sol";

contract HyperdomeContract is ERC721Upgradeable, ERC721EnumerableUpgradeable, OwnableUpgradeable {
    using SafeMathUpgradeable for uint256;
    using AddressUpgradeable for address;
    using CountersUpgradeable for CountersUpgradeable.Counter;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

    CountersUpgradeable.Counter private _tokenIdCounter;
    mapping(address => bool) private adminAccess;

    function initialize() public initializer {
        __ERC721_init("HyperdomeLand", "Hyperdome");
        __Ownable_init();
    }

    function setAdminAccess(address user, bool access) external onlyOwner {
        adminAccess[user] = access;
    }

    function mintHyperdome(address receiver) external onlyAdminAccess returns (uint256) {
        uint256 nextTokenId = _getNextTokenId();
        _mint(receiver, nextTokenId);
        return nextTokenId;
    }

    function _getNextTokenId() private view returns (uint256) {
        return (_tokenIdCounter.current());
    }

    function _mint(address to, uint256 tokenId) internal override(ERC721Upgradeable) {
        super._mint(to, tokenId);
        _tokenIdCounter.increment();
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override(ERC721Upgradeable, ERC721EnumerableUpgradeable) {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721Upgradeable, ERC721EnumerableUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    modifier onlyAdminAccess() {
        require(adminAccess[_msgSender()] == true || _msgSender() == owner(), "Require admin access");
        _;
    }
}

