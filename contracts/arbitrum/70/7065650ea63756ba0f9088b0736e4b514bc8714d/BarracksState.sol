//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./IRandomizer.sol";
import "./IBarracks.sol";
import "./IMagic.sol";
import "./ILegion.sol";
import "./ITreasury.sol";
import "./ILegionMetadataStore.sol";
import "./AdminableUpgradeable.sol";

abstract contract BarracksState is Initializable, IBarracks, AdminableUpgradeable {

    event RecruitTrained(address indexed _owner, uint256 indexed _tokenId);

    IRandomizer public randomizer;
    IMagic public magic;
    ILegion public legion;
    ILegionMetadataStore public legionMetadataStore;
    ITreasury public treasury;

    uint256 public magicCostPerLegion;

    mapping(address => bool) public addressToHasTrained;

    function __BarracksState_init() internal initializer {
        AdminableUpgradeable.__Adminable_init();

        magicCostPerLegion = 10 ether;
    }
}
