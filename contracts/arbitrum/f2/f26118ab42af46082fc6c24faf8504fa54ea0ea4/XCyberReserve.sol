// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "./IERC20.sol";
import "./Initializable.sol";
import "./SafeERC20.sol";

contract XCyberReserve is Initializable {
    using SafeERC20 for IERC20;

    IERC20 public xcyber;

    address public rewarder;
    address public pool;

    /* ============ CONSTRUCTORS ========== */

    function initialize(address _xcyber) external initializer {
        require(_xcyber != address(0), "XCyberReserve::constructor: invalid address");
        xcyber = IERC20(_xcyber);
    }

    /* ============ MUTATIVE ========== */

    function setRewarder(address _rewarder) external returns (bool) {
        require(rewarder == address(0), "XCyberReserve::setRewarder: NOT_ALLOWED");
        rewarder = _rewarder;
        return true;
    }

    function setPool(address _pool) external returns (bool) {
        require(pool == address(0), "XCyberReserve::setPool: NOT_ALLOWED");
        pool = _pool;
        return true;
    }

    function transfer(address _to, uint256 _amount) external {
        require(rewarder == msg.sender || pool == msg.sender, "XCyberReserve::transfer: Only allowed funds can withdraw");
        require(_to != address(0), "XCyberReserve::transfer: Invalid address");
        xcyber.safeTransfer(_to, _amount);
    }
}

