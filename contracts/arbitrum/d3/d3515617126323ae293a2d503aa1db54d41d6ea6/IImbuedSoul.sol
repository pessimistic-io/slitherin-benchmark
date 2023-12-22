// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC721Upgradeable.sol";
import "./ISeedEvolution.sol";

interface IImbuedSoul is IERC721Upgradeable {

    function safeMint(
        address _to,
        uint256 _generation,
        LifeformClass _lifeformClass,
        OffensiveSkill _offensiveSkill,
        SecondarySkill[] calldata _secondarySkills,
        bool _isLandOwner) external;

    function burn(uint256 _tokenId) external;
}
