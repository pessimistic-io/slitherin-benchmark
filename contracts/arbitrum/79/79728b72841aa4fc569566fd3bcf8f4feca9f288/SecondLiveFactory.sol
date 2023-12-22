pragma solidity ^0.8.0;
// SPDX-License-Identifier: MIT

import "./ReentrancyGuard.sol";
import "./SafeMath.sol";

contract SecondLiveFactory is ReentrancyGuard {
    using SafeMath for uint256;

    mapping(address => mapping(uint256 => bool)) public _signIn;

    event eveSignIn(address indexed operator, uint256 indexed date);

    function signIn(uint256 date) external nonReentrant {
        require(
            _signIn[msg.sender][date] == false,
            "SecondLiveFactory: You have signed in!"
        );
        _signIn[msg.sender][date] = true;
        emit eveSignIn(msg.sender, date);
    }
}

