//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./IERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";

import "./TreasurySettings.sol";

contract Treasury is Initializable, TreasurySettings {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    address constant private TREASURY_MULTISIG = 0x0eB5B03c0303f2F47cD81d7BE4275AF8Ed347576;

    function initialize() external initializer {
        TreasurySettings.__TreasurySettings_init();
    }

    function isBridgeWorldPowered() external view contractsAreSet returns(bool) {
        return true;
    }

    function forwardCoinsToMine(uint256 _totalMagicSent) external contractsAreSet onlyAdminOrOwner {
        uint256 _magicToSendToMine = (_totalMagicSent * percentMagicToMine) / 100;
        if(_magicToSendToMine > 0) {
            bool _wasApproved = magic.approve(address(masterOfCoin), _magicToSendToMine);
            require(_wasApproved, "Could not approve magic to mine");

            IMasterOfCoin.CoinStream memory _coinStream = masterOfCoin.getStreamConfig(address(atlasMine));

            if(_coinStream.endTimestamp > block.timestamp) {
                masterOfCoin.grantTokenToStream(address(atlasMine), _magicToSendToMine);
            } else {
                masterOfCoin.grantTokenToStream(middlemanAddress, _magicToSendToMine);
            }
        }
    }

    function withdrawMagic() external virtual onlyAdminOrOwner {
        IERC20Upgradeable _magic = IERC20Upgradeable(address(magic));
        uint256 _magicBalance = _magic.balanceOf(address(this));
        _magic.safeTransfer(TREASURY_MULTISIG, _magicBalance);
        emit Withdraw(address(magic), TREASURY_MULTISIG, _magicBalance);
    }
}
