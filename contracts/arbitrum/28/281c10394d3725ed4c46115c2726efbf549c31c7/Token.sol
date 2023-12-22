// SPDX-License-Identifier: UNLICENSED

import "./ERC20.sol";
import "./IToken.sol";
import "./IRegistry.sol";

pragma solidity >=0.8.0 <0.9.0;

// @address:REGISTRY
IRegistry constant registry = IRegistry(0x0000000000000000000000000000000000000000);

contract Token is ERC20, IToken {

    uint256 public holders;
    uint256 public fundId;

    modifier auth() {
        require(msg.sender == address(registry.interaction()) || msg.sender == address(registry.feeder()), "T/AD"); // access denied
        _;
    }

   // ITKN stands for Invest Token
    constructor (uint256 _fundId) ERC20("Defunds Token", "ITKN") {
        fundId = _fundId;
    }

    /**
     * Called when client investing funds to the buffer contract.
     * Caller is buffer contract
     * Increasing total supply of ITokens. See {ERC20-_mint}
     */
    function mint(address investor, uint256 amount) public override auth {
        _mint(investor, amount);
    }

    /**
     * @dev Destroys `amount` tokens from the caller.
     *
     * See {ERC20-_burn}.
     */
    function burn(uint256 amount) public auth {
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
    function burnFrom(address account, uint256 amount) public override auth {
        uint256 currentAllowance = allowance(account, _msgSender());
        require(currentAllowance >= amount, "ERC20: burn amount exceeds allowance");
        unchecked {
            _approve(account, _msgSender(), currentAllowance - amount);
        }
        _burn(account, amount);
    }

    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        super._afterTokenTransfer(from, to, amount);

        if (balanceOf(to) == amount) {
            holders++;
        }
        if (from != address(0x0) && balanceOf(from) == 0) {
            holders--;
        }
    }
}

