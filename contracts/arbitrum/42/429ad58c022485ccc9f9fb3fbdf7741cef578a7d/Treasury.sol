// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity =0.8.18;

import "./Ownable.sol";
import "./SafeERC20.sol";

import "./ITreasury.sol";

contract Treasury is ITreasury, Ownable {
    using SafeERC20 for IERC20;

    mapping(address debter => mapping(address token => uint amount)) public allowance;
    mapping(address debter => mapping(address token => uint amount)) public debt;

    function setAllowance(address account, address token, uint amount) external onlyOwner {
        allowance[account][token] = amount;
    }

    function withdraw(address token, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(msg.sender, amount);
    }

    function repayDebt(address token, uint256 amount) external {
        uint actualAmount = amount > debt[msg.sender][token] ? debt[msg.sender][token] : amount;
        IERC20(token).safeTransferFrom(msg.sender, address(this), actualAmount);
        debt[msg.sender][token] -= actualAmount;
    }

    function addDebt(address token, uint256 amount) external {
        allowance[msg.sender][token] -= amount;
        debt[msg.sender][token] += amount;
        IERC20(token).safeTransfer(msg.sender, amount);
    }
}
