// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import { ERC20, IERC20 } from "./ERC20.sol";
import { SafeERC20 } from "./SafeERC20.sol";
import { Address } from "./Address.sol";

contract EKEY is ERC20 {
    using SafeERC20 for IERC20;
    using Address for address payable;

    address public operator;

    event UpdateOperator(address user);

    constructor(string memory _name, string memory _symbol, uint256 _totalSupply) ERC20(_name, _symbol) {
        operator = msg.sender;
        _mint(msg.sender, _totalSupply);
    }

    function decimals() public pure virtual override returns (uint8) {
        return 9;
    }

    function updateOperator(address _operator) external {
        require(msg.sender == operator, "ERC20: not operator");
        operator = _operator;
        emit UpdateOperator(operator);
    }

    function operatorWithdraw(address _token, address payable _to, uint256 _amount) external {
        require(msg.sender == operator, "ERC20: not operator");
        if (_token == address(0)) {
            _to.sendValue(_amount);
        } else {
            IERC20(_token).safeTransfer(_to, _amount);
        }
    }
}

