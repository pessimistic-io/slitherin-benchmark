// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "./ERC20Gateway.sol";

interface IMintBurn {
    function mint(address account, uint256 amount) external;

    function burn(address account, uint256 amount) external;
}

contract ERC20Gateway_MintBurn is ERC20Gateway {
    constructor(
        address anyCallProxy,
        uint256 flag,
        address token
    ) ERC20Gateway(anyCallProxy, flag, token) {}

    function description() external pure returns (string memory) {
        return "ERC20Gateway_MintBurn";
    }

    function _swapout(uint256 amount, address sender)
        internal
        override
        returns (bool)
    {
        try IMintBurn(token).burn(sender, amount) {
            return true;
        } catch {
            return false;
        }
    }

    function _swapin(uint256 amount, address receiver)
        internal
        override
        returns (bool)
    {
        try IMintBurn(token).mint(receiver, amount) {
            return true;
        } catch {
            return false;
        }
    }
}

