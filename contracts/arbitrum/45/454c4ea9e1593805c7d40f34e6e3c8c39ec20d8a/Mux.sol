// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "./ERC20PresetMinterPauserUpgradeable.sol";
import "./Initializable.sol";

contract Mux is Initializable, ERC20PresetMinterPauserUpgradeable {
    mapping(address => bool) public isHandler;

    function setHandler(address _handler, bool _isActive) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "ERC20PresetMinterPauser: must have admin role to set");
        isHandler[_handler] = _isActive;
    }

    function initialize(string memory name_, string memory symbol_) public override initializer {
        __ERC20PresetMinterPauser_init(name_, symbol_);
    }

    function burn(address account, uint256 amount) public virtual {
        require(hasRole(MINTER_ROLE, _msgSender()), "ERC20PresetMinterPauser: must have minter role to burn");
        _burn(account, amount);
    }

    function burnFrom(address, uint256) public virtual override {
        revert();
    }

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal override {
        require(isHandler[sender] || isHandler[recipient], "transfer forbidden");
        super._transfer(sender, recipient, amount);
    }
}

