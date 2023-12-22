// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "./IAntiBot.sol";
import "./ERC20Upgradeable.sol";
import "./Initializable.sol";
abstract contract _antiBotUpgradeable is Initializable,  ERC20Upgradeable {
    IAntiBot public antiBot;
    function __Antibot_init_unchained( IAntiBot _antiBotAddress, address _owner ) internal onlyInitializing {
        antiBot = _antiBotAddress;
        antiBot.tokenAdmin(_owner);
    }
    
    function _afterTokenTransfer(address from, address to, uint256 amount) internal virtual override {
        antiBot.onBeforeTokenTransfer(from, to , amount);
        super._afterTokenTransfer(from, to , amount);
    }
}

