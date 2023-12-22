// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.16;

import "./IERC20.sol";
import { ReentrancyGuard } from "./ReentrancyGuard.sol";
import { C } from "./C.sol";
import { LibHedgers } from "./LibHedgers.sol";
import { LibOracle, PositionPrice } from "./LibOracle.sol";
import { LibMaster } from "./LibMaster.sol";
import { SchnorrSign } from "./IMuonV03.sol";

contract AccountFacet is ReentrancyGuard {
    event Deposit(address indexed party, uint256 amount);
    event Withdraw(address indexed party, uint256 amount);
    event Allocate(address indexed party, uint256 amount);
    event Deallocate(address indexed party, uint256 amount);
    event AddFreeMargin(address indexed party, uint256 amount);
    event RemoveFreeMargin(address indexed party, uint256 amount);

    // --------------------------------//
    //----- PUBLIC WRITE FUNCTIONS ----//
    // --------------------------------//

    function deposit(uint256 amount) external {
        _deposit(msg.sender, amount);
    }

    function withdraw(uint256 amount) external {
        _withdraw(msg.sender, amount);
    }

    function allocate(uint256 amount) external {
        _allocate(msg.sender, amount);
    }

    function deallocate(uint256 amount) external {
        _deallocate(msg.sender, amount);
    }

    function depositAndAllocate(uint256 amount) external {
        _deposit(msg.sender, amount);
        _allocate(msg.sender, amount);
    }

    function deallocateAndWithdraw(uint256 amount) external {
        _deallocate(msg.sender, amount);
        _withdraw(msg.sender, amount);
    }

    function addFreeMargin(uint256 amount) external {
        _addFreeMargin(msg.sender, amount);
    }

    function removeFreeMargin() external {
        _removeFreeMargin(msg.sender);
    }

    // --------------------------------//
    //----- PRIVATE WRITE FUNCTIONS ---//
    // --------------------------------//

    function _deposit(address party, uint256 amount) private nonReentrant {
        bool success = IERC20(C.getCollateral()).transferFrom(party, address(this), amount);
        require(success, "Failed to deposit collateral");
        s.ma._accountBalances[party] += amount;

        emit Deposit(party, amount);
    }

    function _withdraw(address party, uint256 amount) private nonReentrant {
        require(s.ma._accountBalances[party] >= amount, "Insufficient account balance");
        s.ma._accountBalances[party] -= amount;
        bool success = IERC20(C.getCollateral()).transfer(party, amount);
        require(success, "Failed to withdraw collateral");

        emit Withdraw(party, amount);
    }

    function _allocate(address party, uint256 amount) private nonReentrant {
        require(s.ma._accountBalances[party] >= amount, "Insufficient account balance");
        s.ma._accountBalances[party] -= amount;
        s.ma._marginBalances[party] += amount;

        emit Allocate(party, amount);
    }

    function _deallocate(address party, uint256 amount) private nonReentrant {
        require(s.ma._marginBalances[party] >= amount, "Insufficient margin balance");
        s.ma._marginBalances[party] -= amount;
        s.ma._accountBalances[party] += amount;

        emit Deallocate(party, amount);
    }

    function _addFreeMargin(address party, uint256 amount) private {
        require(s.ma._marginBalances[party] >= amount, "Insufficient margin balance");
        s.ma._marginBalances[party] -= amount;
        s.ma._lockedMargin[party] += amount;

        emit AddFreeMargin(party, amount);
    }

    function _removeFreeMargin(address party) private {
        require(s.ma._openPositionsCrossLength[party] == 0, "Removal denied");
        require(s.ma._lockedMargin[party] > 0, "No locked margin");

        uint256 amount = s.ma._lockedMargin[party];
        s.ma._lockedMargin[party] = 0;
        s.ma._marginBalances[party] += amount;

        emit RemoveFreeMargin(party, amount);
    }

    // --------------------------------//
    //----- PUBLIC VIEW FUNCTIONS -----//
    // --------------------------------//

    function getAccountBalance(address party) external view returns (uint256) {
        return s.ma._accountBalances[party];
    }

    function getMarginBalance(address party) external view returns (uint256) {
        return s.ma._marginBalances[party];
    }

    function getLockedMargin(address party) external view returns (uint256) {
        return s.ma._lockedMargin[party];
    }

    function getLockedMarginReserved(address party) external view returns (uint256) {
        return s.ma._lockedMarginReserved[party];
    }
}

