// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./SafeMath.sol";
import "./ERC20Burnable.sol";

import "./Operator.sol";

contract RBD is ERC20Burnable, Operator {
    using SafeMath for uint256;


    constructor(

    ) ERC20("RB DAO", "RBD") {
        _mint(msg.sender, 20 ether); // mint 45 RBD for team
    }

    function burn(uint256 amount) public override {
        super.burn(amount);
    }

    function governanceRecoverUnsupported(
        IERC20 _token,
        uint256 _amount,
        address _to
    ) external onlyOperator {
        _token.transfer(_to, _amount);
    }
}

