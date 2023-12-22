//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./IKotEGearBurn.sol";
import "./AdminableUpgradeable.sol";
import "./IKotEKnightGear.sol";
import "./IConsumable.sol";

abstract contract KotEGearBurnState is Initializable, IKotEGearBurn, AdminableUpgradeable {

    event PermitsMinted(address indexed user, uint256 amount);

    uint256 constant public KOTE_ANCIENT_PERMIT_ID = 17;

    IKotEKnightGear public knightGear;
    IConsumable public consumable;

    uint256 public amountMinted;
    uint256 public maxMinted;

    mapping(uint256 => GearRarity) public gearIdToRarity;
    mapping(GearRarity => uint256) public rarityToBurnAmounts;

    function __KotEGearBurnState_init() internal initializer {
        AdminableUpgradeable.__Adminable_init();

        maxMinted = 600;

        _setRarity(16, GearRarity.Epic);
        _setRarity(17, GearRarity.Epic);
        _setRarity(18, GearRarity.Epic);
        _setRarity(19, GearRarity.Epic);
        _setRarity(36, GearRarity.Epic);
        _setRarity(37, GearRarity.Epic);
        _setRarity(38, GearRarity.Epic);
        _setRarity(63, GearRarity.Epic);
        _setRarity(64, GearRarity.Epic);
        _setRarity(65, GearRarity.Epic);
        _setRarity(66, GearRarity.Epic);
        _setRarity(86, GearRarity.Epic);
        _setRarity(87, GearRarity.Epic);
        _setRarity(88, GearRarity.Epic);
        _setRarity(106, GearRarity.Epic);
        _setRarity(107, GearRarity.Epic);
        _setRarity(108, GearRarity.Epic);
        _setRarity(126, GearRarity.Epic);
        _setRarity(127, GearRarity.Epic);
        _setRarity(128, GearRarity.Epic);
        _setRarity(146, GearRarity.Epic);
        _setRarity(147, GearRarity.Epic);
        _setRarity(148, GearRarity.Epic);
        _setRarity(163, GearRarity.Epic);
        _setRarity(164, GearRarity.Epic);
        _setRarity(165, GearRarity.Epic);
        _setRarity(178, GearRarity.Epic);
        _setRarity(179, GearRarity.Epic);
        _setRarity(189, GearRarity.Epic);
        _setRarity(190, GearRarity.Epic);

        _setRarity(20, GearRarity.Legendary);
        _setRarity(21, GearRarity.Legendary);
        _setRarity(22, GearRarity.Legendary);
        _setRarity(23, GearRarity.Legendary);
        _setRarity(39, GearRarity.Legendary);
        _setRarity(40, GearRarity.Legendary);
        _setRarity(67, GearRarity.Legendary);
        _setRarity(68, GearRarity.Legendary);
        _setRarity(69, GearRarity.Legendary);
        _setRarity(70, GearRarity.Legendary);
        _setRarity(89, GearRarity.Legendary);
        _setRarity(90, GearRarity.Legendary);
        _setRarity(109, GearRarity.Legendary);
        _setRarity(110, GearRarity.Legendary);
        _setRarity(129, GearRarity.Legendary);
        _setRarity(130, GearRarity.Legendary);
        _setRarity(149, GearRarity.Legendary);
        _setRarity(150, GearRarity.Legendary);
        _setRarity(166, GearRarity.Legendary);
        _setRarity(167, GearRarity.Legendary);
        _setRarity(168, GearRarity.Legendary);
        _setRarity(180, GearRarity.Legendary);
        _setRarity(181, GearRarity.Legendary);
        _setRarity(191, GearRarity.Legendary);
        _setRarity(192, GearRarity.Legendary);

        _setBurnAmount(GearRarity.Epic, 5);
        _setBurnAmount(GearRarity.Legendary, 1);
    }

    function _setRarity(uint256 _id, GearRarity _rarity) private {
        gearIdToRarity[_id] = _rarity;
    }

    function _setBurnAmount(GearRarity _rarity, uint256 _amount) private {
        rarityToBurnAmounts[_rarity] = _amount;
    }
}

enum GearRarity {
    Common,
    Uncommon,
    Rare,
    Epic,
    Legendary
}
