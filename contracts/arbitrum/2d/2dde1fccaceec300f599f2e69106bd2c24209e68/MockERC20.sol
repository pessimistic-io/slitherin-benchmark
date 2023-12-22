//SPDX-License-Identifier: UNLCIENSED

pragma solidity >=0.8.0;

import {ERC20} from "./ERC20.sol";
import "./console.sol";

/**
 * @dev THIS CONTRACT IS FOR TESTING PURPOSES ONLY.
 */
contract MockERC20 is ERC20 {
    uint8 internal decimals_;

    constructor(string memory _name, string memory _symbol, uint8 _decimals) ERC20(_name, _symbol) {
        decimals_ = _decimals;
    }

    function mint(uint256 _amount) public {
        _mint(msg.sender, _amount);
    }

    function mintTo(uint256 _amount, address _to) public {
        _mint(_to, _amount);
    }

    function decimals() public view virtual override returns (uint8) {
        return decimals_;
    }

    /**
     * @dev Destroys `amount` tokens from the caller.
     *
     * See {ERC20-_burn}.
     */
    function burn(uint256 amount) public virtual {
        _burn(_msgSender(), amount);
    }

    /**
     * @dev Destroys `amount` tokens from `account`, deducting from the caller's
     * allowance.
     *
     * See {ERC20-_burn} and {ERC20-allowance}.
     *
     * Requirements:
     *
     * - the caller must have allowance for ``accounts``'s tokens of at least
     * `amount`.
     */
    function burnFrom(address account, uint256 amount) public virtual {
        _spendAllowance(account, _msgSender(), amount);
        _burn(account, amount);
    }
}

