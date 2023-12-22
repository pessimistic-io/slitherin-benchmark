// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "./ERC677Gateway.sol";

interface IMintBurn {
    function mint(address account, uint256 amount) external;

    function burn(address account, uint256 amount) external;
}

contract ERC677Gateway_MintBurn is ERC677Gateway {
    constructor(
        address anyCallProxy,
        uint256 flag,
        address token
    ) ERC677Gateway(anyCallProxy, flag, token) {}

    function description() external pure returns (string memory) {
        return "ERC677Gateway_MintBurn";
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

