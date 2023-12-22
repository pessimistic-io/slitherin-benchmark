// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import "./IERC20.sol";
import "./Admin.sol";
import "./SafeERC20.sol";

contract Compensation is Admin {

    using SafeERC20 for IERC20;

    event Claim(address indexed account, uint256 amount);

    address public immutable token;

    uint256 public immutable deadline;

    mapping (address => uint256) public compensations;

    constructor (address token_, uint256 deadline_) {
        token = token_;
        deadline = deadline_;
    }

    struct Info {
        address account;
        uint256 amount;
    }

    function initialize(Info[] calldata info) external _onlyAdmin_ {
        for (uint256 i = 0; i < info.length; i++) {
            compensations[info[i].account] = info[i].amount;
        }
    }

    function withdraw(address to) external _onlyAdmin_ {
        require(block.timestamp > deadline, 'Compensation.withdraw: not expired');
        IERC20(token).safeTransfer(to, IERC20(token).balanceOf(address(this)));
    }

    function claim() external {
        require(block.timestamp <= deadline, 'Compensation.Claim: expired');
        uint256 amount = compensations[msg.sender];
        require(amount > 0, 'Compensation.Claim: no compensation to claim');
        compensations[msg.sender] = 0;
        IERC20(token).safeTransfer(msg.sender, amount);
        emit Claim(msg.sender, amount);
    }

}

