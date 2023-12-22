// SPDX-License-Identifier: MIT LICENSE
pragma solidity ^0.8.0;

import "./IERC20Upgradeable.sol";
import "./IPeekABoo.sol";
import "./ITraits.sol";
import "./ILevel.sol";

interface IInGame {
    function buyTraits(
        uint256 tokenId,
        uint256[] calldata traitTypes,
        uint256[] calldata traitIds,
        uint256 amount
    ) external;

    function buyAbilities(
        uint256 tokenId,
        uint256[] calldata abilities,
        uint256 amount
    ) external;

    function tierUp(uint256 tokenId, uint64 toTier) external;

    function getBoughtTraitCount(uint256 tokenId, uint256 rarity)
        external
        returns (uint256);

    function isBoughtTrait(
        uint256 tokenId,
        uint256 traitType,
        uint256 traitId
    ) external returns (bool);

    function isBoughtAbility(uint256 tokenId, uint256 ability) external returns (bool);

    function setBOO(address _boo) external;

    function setMagic(address _magic) external;

    function setPeekABoo(address _pab) external;

    function setTraits(address _traits) external;

    function setLevel(address _level) external;

    function setTraitPriceRate(uint256 rate) external;

    function setAbilityPriceRate(uint256 rate) external;
}

