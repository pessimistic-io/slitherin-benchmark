//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./ERC721Upgradeable.sol";

import "./IImbuedSoul.sol";
import "./AdminableUpgradeable.sol";

abstract contract ImbuedSoulState is Initializable, IImbuedSoul, ERC721Upgradeable, AdminableUpgradeable {

    event ImbuedSoulCreate(address indexed _owner, uint256 indexed _tokenId, ImbuedSoulInfo _info);
    event Staked(uint256 indexed tokenId);
    event Unstaked(uint256 indexed tokenId);

    uint256 public tokenIdCur;

    mapping(uint256 => ImbuedSoulInfo) tokenIdtoInfo;

    string public imageURI;

    mapping(LifeformClass => string) public classToString;
    mapping(OffensiveSkill => string) public offensiveSkillToString;
    mapping(SecondarySkill => string) public secondarySkillToString;

    // Mapping from owner to list of owned token IDs
    mapping(address => mapping(uint256 => uint256)) internal _ownedTokens;

    // Mapping from token ID to index of the owner tokens list
    mapping(uint256 => uint256) internal _ownedTokensIndex;

    // Mapping from token Id to staked
    mapping(uint256 => bool) internal _stakedTokens;

    bool public stakingPaused;

    function __ImbuedSoulState_init() internal initializer {
        AdminableUpgradeable.__Adminable_init();
        ERC721Upgradeable.__ERC721_init("ImbuedSoul", "SOUL");

        tokenIdCur = 1;
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual override {
        super._beforeTokenTransfer(from, to, tokenId);

        require(
            !_stakedTokens[tokenId],
            "ImbuedSoul: Can't transfer staked token"
        );

        uint256 length = ERC721Upgradeable.balanceOf(to);

        _ownedTokens[to][length] = tokenId;
        _ownedTokensIndex[tokenId] = length;

        if (from == address(0)) {
            return;
        }

        uint256 lastTokenIndex = ERC721Upgradeable.balanceOf(from) - 1;
        uint256 tokenIndex = _ownedTokensIndex[tokenId];

        // When the token to delete is the last token, the swap operation is unnecessary
        if (tokenIndex != lastTokenIndex) {
            uint256 lastTokenId = _ownedTokens[from][lastTokenIndex];

            _ownedTokens[from][tokenIndex] = lastTokenId; // Move the last token to the slot of the to-delete token
            _ownedTokensIndex[lastTokenId] = tokenIndex; // Update the moved token's index
        }

        // This also deletes the contents at the last position of the array
        delete _ownedTokensIndex[tokenId];
        delete _ownedTokens[from][lastTokenIndex];
    }
}

struct ImbuedSoulInfo {
    // The generation this imbued soul was FROM.
    uint256 generation;
    LifeformClass lifeformClass;
    OffensiveSkill offensiveSkill;
    SecondarySkill[] secondarySkills;
    bool isLandOwner;
    uint256 lifeformID;
}

struct OwnedToken {
    address owner;
    uint256[] tokenIds;
}

