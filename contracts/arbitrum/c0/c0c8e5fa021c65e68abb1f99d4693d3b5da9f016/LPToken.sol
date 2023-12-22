// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import {ERC20Burnable} from "./ERC20Burnable.sol";
import {ERC20} from "./ERC20.sol";

/// @title LP Token
/// @author LevelFinance
/// @notice User will receive LP Token when deposit their token to protocol; and it can be redeem to receive
/// any token of their choice
contract LPToken is ERC20Burnable {
    error InvalidAddress();
    error OnlyMinter();

    address public immutable minter;

    constructor(string memory _name, string memory _symbol, address _minter) ERC20(_name, _symbol) {
        if (_minter == address(0)) {
            revert InvalidAddress();
        }
        minter = _minter;
    }

    function mint(address _to, uint256 _amount) external {
        if (msg.sender != minter) {
            revert OnlyMinter();
        }
        _mint(_to, _amount);
    }
}

