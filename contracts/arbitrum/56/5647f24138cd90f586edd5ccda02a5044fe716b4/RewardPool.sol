// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.21;

import { SafeERC20, IERC20 } from "./SafeERC20.sol";
import { Ownable } from "./Ownable.sol";

contract RewardPool is Ownable {
    using SafeERC20 for IERC20;

    address public immutable flipGame;

    error Unauthorized();

    event PayOutPaid(address indexed player, address indexed betToken, uint256 amount);

    constructor(address _flipGame, address _owner) Ownable(_owner) {
        flipGame = _flipGame;
    }

    function payout(address _player, address _betToken, uint256 _amount) external {
        if (msg.sender != flipGame) revert Unauthorized();
        if (_betToken == address(0)) {
            payable(_player).transfer(_amount);
        } else {
            IERC20(_betToken).safeTransfer(_player, _amount);
        }
        emit PayOutPaid(_player, _betToken, _amount);
    }

    function withdrawToken(address _token, uint256 _amount) external onlyOwner {
        IERC20(_token).safeTransfer(msg.sender, _amount);
    }

    function withdrawNativeToken(uint256 _amount) external onlyOwner {
        payable(msg.sender).transfer(_amount);
    }

    receive() external payable { }
}

