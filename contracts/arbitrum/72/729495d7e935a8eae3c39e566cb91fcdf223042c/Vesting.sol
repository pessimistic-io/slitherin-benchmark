// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {ERC20, SafeTransferLib} from "./SafeTransferLib.sol";

// Disclamer: avoid using this contract with feeOnTransfer or rebase tokens.
contract Vesting {

    using SafeTransferLib for ERC20;

    address internal _token;
    uint256 internal _totalAmount;
    uint256 internal _claimed;
    address internal _recipient;
    uint256 internal _startTime;
    uint256 internal _endTime;

    event SetRecipient(address indexed newRecipient);

    modifier onlyRecipient() {
        require(msg.sender == _recipient, "Only recipient.");
        _;
    }

    function init(
        address token,
        uint256 amount,
        address recipient,
        uint256 startTime,
        uint256 endTime
    ) external {
        require(address(_token) == address(0), "Already initialised.");
        require(startTime < endTime, "Invalid timeframe.");
        require(ERC20(token).balanceOf(address(this)) == amount, "Incorrect token amount.");
        _token = token;
        _totalAmount = amount;
        _recipient = recipient;
        _startTime = startTime;
        _endTime = endTime;
        emit SetRecipient(_recipient);
    }

    function getVestingSchedule() external view returns (
        address token,
        uint256 totalAmount,
        address recipient,
        uint256 startTime,
        uint256 endTime
    ) {
        return (_token, _totalAmount, _recipient, _startTime, _endTime);
    }

    function getVestingStatus() public view returns (uint256 claimed, uint256 claimable, uint256 pending) {
        claimed = _claimed;
        uint256 vested;
        (vested, pending) = _getVestingStatus(_startTime, block.timestamp, _endTime, _totalAmount);
        claimable = vested - claimed;
    }

    function claim() external onlyRecipient returns (uint256 amount) {
        (, amount, ) = getVestingStatus();
        _claimed += amount;
        ERC20(_token).safeTransfer(_recipient, amount);
    }

    function changeRecipient(address newRecipient) external onlyRecipient {
        _recipient = newRecipient;
        emit SetRecipient(newRecipient);
    }

    function _getVestingStatus(
        uint256 startTime,
        uint256 currentTime,
        uint256 endTime,
        uint256 totalAmount
    ) internal pure returns (uint256 vested, uint256 pending) {
        if (currentTime < startTime) return (0, totalAmount);
        if (currentTime >= endTime) return (totalAmount, 0);
        uint256 passedTime = currentTime - startTime;
        uint256 totalTime = endTime - startTime;
        vested = totalAmount * passedTime / totalTime;
        return (vested, totalAmount - vested);
    }

}

