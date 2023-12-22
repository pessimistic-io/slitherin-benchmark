//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./KotEGearBurnContracts.sol";

contract KotEGearBurn is Initializable, KotEGearBurnContracts {

    function initialize() external initializer {
        KotEGearBurnContracts.__KotEGearBurnContracts_init();
    }

    function setMaxMinted(uint256 _maxMinted) external onlyAdminOrOwner {
        maxMinted = _maxMinted;
    }

    function mintPermit(MintPermitParams[] calldata _params) public whenNotPaused contractsAreSet onlyEOA {
        require(amountMinted + _params.length <= maxMinted, "Max burns reached");
        require(_params.length > 0, "Non-zero length required");

        amountMinted += _params.length;

        for(uint256 i = 0; i < _params.length; i++) {
            _mintPermit(_params[i]);
        }

        emit PermitsMinted(msg.sender, _params.length);
    }

    function _mintPermit(MintPermitParams calldata _params) private {
        require(_params.tokens.length > 0, "No tokens provided");

        // Assume the rarity of the first id is the rarity of all the ids they are trying to burn.
        // As the burns occur, we will double check that the ids match this rarity
        //
        GearRarity _rarity = gearIdToRarity[_params.tokens[0].id];

        require(_rarity == GearRarity.Epic || _rarity == GearRarity.Legendary, "Only epic and legendary gear can be burnt");

        uint256 _targetAmount = rarityToBurnAmounts[_rarity];

        uint256 _actualAmount;

        for(uint256 i = 0; i < _params.tokens.length; i++) {
            MintPermitToken calldata _token = _params.tokens[i];
            GearRarity _rarityOfGear = gearIdToRarity[_token.id];
            require(_rarityOfGear == _rarity, "Not all gear rarities match");

            _actualAmount += _token.amount;
            knightGear.burn(msg.sender, _token.id, _token.amount);
        }

        require(_targetAmount == _actualAmount, "Did not provide the correct amount for this rarity of gear");

        consumable.mint(msg.sender, KOTE_ANCIENT_PERMIT_ID, 1);
    }
}

struct MintPermitParams {
    MintPermitToken[] tokens;
}

struct MintPermitToken {
    uint128 id;
    uint128 amount;
}
