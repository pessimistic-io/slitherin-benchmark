// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity =0.8.14;

import { ERC20 } from "./ERC20.sol";
import { Ownable } from "./Ownable.sol";
import { IVQuote } from "./IVQuote.sol";
import { IVPoolWrapper } from "./IVPoolWrapper.sol";

contract VQuote is IVQuote, ERC20('Rage Trade Virtual Quote Token', 'vQuote'), Ownable {
    mapping(address => bool) public isAuth;

    uint8 immutable _decimals;

    constructor(uint8 decimals_) {
        _decimals = decimals_;
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256
    ) internal view override {
        // transfer cases:
        // - vPoolWrapper mints tokens at uniswap pool address
        // - uniswap v3 pool transfers tokens to vPoolWrapper
        // - vPoolWrapper burns all tokens it has, at its own address
        if (!(from == address(0) || to == address(0) || isAuth[from] || isAuth[to])) {
            revert Unauthorised();
        }
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    function authorize(address vPoolWrapper) external onlyOwner {
        isAuth[vPoolWrapper] = true;
    }

    error Unauthorised();

    function mint(address account, uint256 amount) external {
        if (!isAuth[msg.sender]) {
            revert Unauthorised();
        }
        _mint(account, amount);
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }
}

