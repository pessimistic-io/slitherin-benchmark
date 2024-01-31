// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./Ownable.sol";
import "./SafeMath.sol";

/// @title STARL PassPoints Router
/// @notice A contract to receive payments for PassPoints purchase.
contract PassPointsRouter is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    event STARLTokenBurnEvent(uint256 amount);
    event Transfer(address indexed from, address indexed to, uint256 value);

    IERC20 public _starlToken;
    address public _dead = address(0xdead);
    uint256 public _burntFee = 3;

    constructor(IERC20 starlToken, uint256 burntFee) {
        require(address(starlToken) != address(0x00), "Invalid token");
        require(burntFee > 0, "Invalid burnt fee");
        require(burntFee < 50, "Invalid burnt fee");

        _starlToken = starlToken;
        _burntFee = burntFee;
    }

    receive() external payable {
        emit Transfer(msg.sender, address(this), msg.value);
    }

    // withdraw ETH
    function withdraw() public onlyOwner {
        require(payable(msg.sender).send(address(this).balance));
    }

    // withdraw token
    function withdrawToken(IERC20 token) public onlyOwner {
        require(address(token) != address(0x00), "Invalid token");
        require(token.balanceOf(address(this)) > 0, "No balance");

        // if token is STARL
        if (token == _starlToken) {
            // burn some of STARL based on _burntFee
            uint256 balance = _starlToken.balanceOf(address(this));
            uint256 burnAmount = balance.mul(_burntFee).div(100);
            _starlToken.transfer(_dead, burnAmount);
            _starlToken.transfer(msg.sender, balance.sub(burnAmount));

            emit STARLTokenBurnEvent(burnAmount);
        } else {
            token.transfer(msg.sender, token.balanceOf(address(this)));
        }
    }
}

