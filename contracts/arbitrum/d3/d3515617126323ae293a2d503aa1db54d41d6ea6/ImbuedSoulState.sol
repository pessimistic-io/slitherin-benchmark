//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./ERC721Upgradeable.sol";

import "./IImbuedSoul.sol";
import "./AdminableUpgradeable.sol";

abstract contract ImbuedSoulState is Initializable, IImbuedSoul, ERC721Upgradeable, AdminableUpgradeable {

    event ImbuedSoulCreate(address indexed _owner, uint256 indexed _tokenId, ImbuedSoulInfo _info);

    uint256 public tokenIdCur;

    mapping(uint256 => ImbuedSoulInfo) tokenIdtoInfo;

    function __ImbuedSoulState_init() internal initializer {
        AdminableUpgradeable.__Adminable_init();
        ERC721Upgradeable.__ERC721_init("ImbuedSoul", "SOUL");

        tokenIdCur = 1;
    }
}

struct ImbuedSoulInfo {
    // The generation this imbued soul was FROM.
    uint256 generation;
    LifeformClass lifeformClass;
    OffensiveSkill offensiveSkill;
    SecondarySkill[] secondarySkills;
    bool isLandOwner;
}
