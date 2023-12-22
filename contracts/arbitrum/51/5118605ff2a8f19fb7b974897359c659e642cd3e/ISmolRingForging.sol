// SPDX-License-Identifier: MIT

pragma solidity ^0.8.11;

import "./IERC721Enumerable.sol";

/**
 * @title  ISmolRingForging interface
 * @author Archethect
 * @notice This interface contains all functionalities for forging rings.
 */
interface ISmolRingForging {
    event RingUpgraded(address sender, uint256 ringId, uint256 ringType);
    event StartForgeSlot(address sender, uint256 requestId, uint8 oddMultiplier);

    struct ForgeType {
        bool valid;
        bool slot;
        address contractAddress;
        // 0 = ERC1155, 1 = ERC20
        uint8 tokenType;
        uint256 id;
        uint256 requiredAmount;
        uint256 rewardFactor;
        uint256 maxForges;
        string imageURI;
        string name;
    }

    struct SlotRequest {
        uint256 id;
        uint8 oddsMultiplier;
    }

    struct SlotOption {
        uint256 ringType;
        uint256 odds;
    }

    function forgeRing(uint256 ringId, uint256 ringType) external;

    function startForgeSlot(uint256 ringId, uint8 oddsMultiplier) external;

    function stopForgeSlot(uint256 ringId) external;

    function hasAvailableSlotRingsToForge() external view returns (bool);

    function setAllowedForges(uint256[] calldata ringTypes, ForgeType[] calldata forgeTypes) external;

    function removeAllowedForgeTypes(uint256[] calldata ringTypes) external;

    function maxForgesPerRingType(uint256 ringType) external view returns (uint256);

    function setForgeEnabled(bool status) external;

    function setSlotEnabled(bool status) external;

    function setSlotOptions(uint256[] calldata _ringIds, uint32[] calldata _slotOdds) external;

    function setMagicSlotPrice(uint256 _magicSlotPrice) external;

    function setSmolTreasureIdForSlot(uint256 _smolTreasureIdForSlot) external;

    function getAllowedForges(uint256 index) external view returns (ForgeType memory);

    function setRandomizer(address _randomizer) external;
}

