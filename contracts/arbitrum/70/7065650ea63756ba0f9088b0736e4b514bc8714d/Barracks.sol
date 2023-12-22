//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./BarracksContracts.sol";

contract Barracks is Initializable, BarracksContracts {

    function initialize() external initializer {
        BarracksContracts.__BarracksContracts_init();
    }

    function setMagicCostPerLegion(uint256 _magicCostPerLegion) external onlyAdminOrOwner {
        magicCostPerLegion = _magicCostPerLegion;
    }

    function trainRecruit()
    external
    whenNotPaused
    onlyEOA
    contractsAreSet
    {
        require(!addressToHasTrained[msg.sender], "Already trained");
        require(magicCostPerLegion > 0, "Magic cost not set");

        addressToHasTrained[msg.sender] = true;

        bool _wasMagicTransferred = magic.transferFrom(msg.sender, address(treasury), magicCostPerLegion);
        require(_wasMagicTransferred, "Magic not transferred");

        treasury.forwardCoinsToMine(magicCostPerLegion);

        uint256 _newlyMintedTokenId = legion.safeMint(msg.sender);

        legionMetadataStore.setInitialMetadataForLegion(msg.sender, _newlyMintedTokenId, LegionGeneration.RECRUIT, LegionClass.RECRUIT, LegionRarity.RECRUIT, 0);

        emit RecruitTrained(msg.sender, _newlyMintedTokenId);
    }

    function trainRecruitAdmin(address _to)
    external
    whenNotPaused
    onlyEOA
    contractsAreSet
    onlyAdminOrOwner
    {
        require(!addressToHasTrained[_to], "Already trained");

        addressToHasTrained[_to] = true;

        uint256 _newlyMintedTokenId = legion.safeMint(_to);

        legionMetadataStore.setInitialMetadataForLegion(_to, _newlyMintedTokenId, LegionGeneration.RECRUIT, LegionClass.RECRUIT, LegionRarity.RECRUIT, 0);

        emit RecruitTrained(_to, _newlyMintedTokenId);
    }
}
