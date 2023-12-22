//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./WartlocksHallowSettings.sol";

contract WartlocksHallow is Initializable, WartlocksHallowSettings {

    function initialize() external initializer {
        WartlocksHallowSettings.__WartlocksHallowSettings_init();
    }

    function depositMagic(
        uint128 _amount)
    external
    onlyEOA
    whenNotPaused
    contractsAreSet
    {
        require(world.balanceOf(msg.sender) > 0, "WartlocksHallow: Must have toad staked");

        magicStaking.deposit(msg.sender, _amount);

        // Give badge
        badgez.mintIfNeeded(msg.sender, stakeMagicBadgeId);

        uint128 _totalAmountStaked = magicStaking.stakeAmount(msg.sender);
        if(_totalAmountStaked >= 100 ether) {
            badgez.mintIfNeeded(msg.sender, stake100MagicBadgeId);
        }
    }

    function withdrawMagic()
    external
    onlyEOA
    whenNotPaused
    contractsAreSet
    {
        magicStaking.withdraw(msg.sender);
    }

    function burnItems(
        BurnItemsParams[] calldata _burnItemParams)
    external
    onlyEOA
    whenNotPaused
    contractsAreSet
    {
        require(isCroakshirePowered(), "Croakshire must be powered");
        require(_burnItemParams.length > 0, "Bad length");

        require(currentItemsBurnt < numberItemsToBurn, "Already burnt enough itemz!");

        for(uint256 i = 0; i < _burnItemParams.length; i++) {
            BurnItemsParams calldata _params = _burnItemParams[i];
            require(itemIdToIsBurnable[_params.itemId], "Not burnable");
            require(_params.amount > 0, "Bad amount");

            itemz.burn(msg.sender, _params.itemId, _params.amount);

            currentItemsBurnt += _params.amount;

            emit ItemsBurnt(_params);
        }

        badgez.mintIfNeeded(msg.sender, feedTheCauldronBadgeId);
    }

    // No longer need to stake magic to power croakshire
    //
    function isCroakshirePowered() public pure returns(bool) {
        return true;
    }
}
