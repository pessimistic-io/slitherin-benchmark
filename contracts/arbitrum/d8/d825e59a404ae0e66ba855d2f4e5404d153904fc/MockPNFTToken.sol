// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.7.6;

import "./Initializable.sol";
import "./ERC20PresetMinterPauserUpgradeable.sol";

contract MockPNFTToken is ERC20PresetMinterPauserUpgradeable {
    function __MockPNFTToken_init(string memory name, string memory symbol, uint8 decimal) public initializer {
        __ERC20PresetMinterPauser_init(name, symbol);
        _setupDecimals(decimal);
    }

    function setMinter(address minter) external {
        grantRole(MINTER_ROLE, minter);
    }

    function adminTransfer(address sender, address recipient, uint256 amount) external {
        require(hasRole(MINTER_ROLE, _msgSender()), "MockPNFTToken: must have minter role to transfer");
        _transfer(sender, recipient, amount);
    }

    function adminBurn(address recipient, uint256 amount) external {
        require(hasRole(MINTER_ROLE, _msgSender()), "MockPNFTToken: must have minter role to transfer");
        _burn(recipient, amount);
    }
}

