// SPDX-License-Identifier: NO LICENSE
pragma solidity ^0.8.0;

import "./SafeERC20.sol";

contract CyOpVoid {
    using SafeERC20 for IERC20;

    address public constant CYOP = 0xDF0301d1964559D1fb29e41B68E15aCBfe896955;

    mapping(uint256 => uint256) public roundToken;

    event Void(uint256 round, uint256 amount, uint256 timestamp);

    function voidBurned(uint256 _amount, uint256 _round) external {
        IERC20(CYOP).safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );
        roundToken[_round] += _amount;
        emit Void(_round, _amount, block.timestamp);
    }

}
