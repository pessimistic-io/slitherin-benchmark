//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./TreasurySettings.sol";

contract Treasury is Initializable, TreasurySettings {

    function initialize() external initializer {
        TreasurySettings.__TreasurySettings_init();
    }

    function isBridgeWorldPowered() external view contractsAreSet returns(bool) {
        return atlasMine.utilization() >= utilNeededToPowerBW;
    }

    function forwardCoinsToMine(uint256 _totalMagicSent) external contractsAreSet onlyAdminOrOwner {
        uint256 _magicToSendToMine = (_totalMagicSent * percentMagicToMine) / 100;
        if(_magicToSendToMine > 0) {
            bool _wasApproved = magic.approve(address(masterOfCoin), _magicToSendToMine);
            require(_wasApproved, "Could not approve magic to mine");

            masterOfCoin.grantTokenToStream(address(atlasMine), _magicToSendToMine);
        }
    }
}
