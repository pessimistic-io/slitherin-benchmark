// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.16;

import "./IERC20.sol";
import { ReentrancyGuard } from "./ReentrancyGuard.sol";
import { C } from "./C.sol";
import { LibHedgers } from "./LibHedgers.sol";
import { LibOracle, PositionPrice } from "./LibOracle.sol";
import { LibMaster } from "./LibMaster.sol";
import { Position } from "./LibAppStorage.sol";
import { SchnorrSign } from "./IMuonV03.sol";

contract AccountFacet is ReentrancyGuard {
    event Deposit(address indexed party, uint256 amount);
    event Withdraw(address indexed party, uint256 amount);
    event Allocate(address indexed party, uint256 amount);
    event Deallocate(address indexed party, uint256 amount);
    event AddFreeMarginIsolated(address indexed party, uint256 amount, uint256 indexed positionId);
    event AddFreeMarginCross(address indexed party, uint256 amount);
    event RemoveFreeMarginCross(address indexed party, uint256 amount);

    /*------------------------*
     * PUBLIC WRITE FUNCTIONS *
     *------------------------*/

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

    function addFreeMarginIsolated(uint256 amount, uint256 positionId) external {
        _addFreeMarginIsolated(msg.sender, amount, positionId);
    }

    function addFreeMarginCross(uint256 amount) external {
        _addFreeMarginCross(msg.sender, amount);
    }

    function removeFreeMarginCross() external {
        _removeFreeMarginCross(msg.sender);
    }

    /*-------------------------*
     * PRIVATE WRITE FUNCTIONS *
     *-------------------------*/

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

    function _addFreeMarginIsolated(address party, uint256 amount, uint256 positionId) private nonReentrant {
        Position storage position = s.ma._allPositionsMap[positionId];
        require(position.partyB == party, "Not partyB");

        require(s.ma._marginBalances[party] >= amount, "Insufficient margin balance");
        s.ma._marginBalances[party] -= amount;
        position.lockedMarginB += amount;

        emit AddFreeMarginIsolated(party, amount, positionId);
    }

    function _addFreeMarginCross(address party, uint256 amount) private nonReentrant {
        require(s.ma._marginBalances[party] >= amount, "Insufficient margin balance");
        s.ma._marginBalances[party] -= amount;
        s.ma._crossLockedMargin[party] += amount;

        emit AddFreeMarginCross(party, amount);
    }

    function _removeFreeMarginCross(address party) private nonReentrant {
        require(s.ma._openPositionsCrossLength[party] == 0, "Removal denied");
        require(s.ma._crossLockedMargin[party] > 0, "No locked margin");

        uint256 amount = s.ma._crossLockedMargin[party];
        s.ma._crossLockedMargin[party] = 0;
        s.ma._marginBalances[party] += amount;

        emit RemoveFreeMarginCross(party, amount);
    }

    /*-----------------------*
     * PUBLIC VIEW FUNCTIONS *
     *-----------------------*/

    function getAccountBalance(address party) external view returns (uint256) {
        return s.ma._accountBalances[party];
    }

    function getMarginBalance(address party) external view returns (uint256) {
        return s.ma._marginBalances[party];
    }

    function getLockedMargin(address party) external view returns (uint256) {
        return s.ma._crossLockedMargin[party];
    }

    function getLockedMarginReserved(address party) external view returns (uint256) {
        return s.ma._crossLockedMarginReserved[party];
    }
}

