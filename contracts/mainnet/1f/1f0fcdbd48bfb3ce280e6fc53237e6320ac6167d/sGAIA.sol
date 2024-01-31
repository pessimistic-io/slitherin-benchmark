// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./ERC20_IERC20.sol";
import "./draft-IERC20Permit.sol";
import "./SafeCast.sol";
import "./IsGAIA.sol";

contract sGAIA is IsGAIA {
    using SafeCast for uint256;

    address public immutable GAIA;
    string public constant name = "Staked GAIA";
    string public constant symbol = "sGAIA";
    uint8 public immutable decimals;
    uint256 public immutable MAX_DURATION;

    mapping(address => Locked) internal _locked;

    constructor(address _GAIA) {
        GAIA = _GAIA;
        decimals = 26;
        MAX_DURATION = 3600 * 24 * 365 * 4;
    }

    function deposit(
        address to,
        uint256 amount,
        uint256 duration
    ) external {
        _deposit(to, amount, duration);
    }

    function depositWithPermit(
        address to,
        uint256 amount,
        uint256 duration,
        uint256 deadline,
        bytes32 r,
        bytes32 s,
        uint8 v
    ) external {
        IERC20Permit(GAIA).permit(msg.sender, address(this), amount, deadline, v, r, s);
        _deposit(to, amount, duration);
    }

    function _deposit(
        address to,
        uint256 amount,
        uint256 duration
    ) internal {
        if (to == address(0)) revert AddressZero();
        if (amount == 0) {
            if (duration == 0) revert BothParamsZero();
            if (to != msg.sender) revert AddressToShouldBeMsgSender();
        }
        uint256 oldAmount = _locked[to].depositAmount;
        uint256 oldUnlockTime = _locked[to].unlockTime;

        uint256 newAmount = oldAmount + amount;
        uint256 newUnlockTime = oldUnlockTime > block.timestamp ? oldUnlockTime + duration : block.timestamp + duration;

        if (newAmount == 0) revert NewAmountZero();
        if (newUnlockTime <= block.timestamp) revert DurationZero();
        if (newUnlockTime > block.timestamp + MAX_DURATION) revert ExceedMaxDuration(newUnlockTime);

        if (amount != 0) _locked[to].depositAmount = newAmount.toUint128();
        if (duration != 0) _locked[to].unlockTime = newUnlockTime.toUint128();

        if (amount != 0) IERC20(GAIA).transferFrom(msg.sender, address(this), amount);
        emit Deposit(to, msg.sender, amount, newUnlockTime, block.timestamp);
        emit Slope(to, newAmount, newUnlockTime);
    }

    function withdraw(address to) external {
        uint256 unlockTime = _locked[msg.sender].unlockTime;
        if (unlockTime > block.timestamp) revert NotAvailableYet(unlockTime - block.timestamp);
        else if (unlockTime == 0) revert NoDepositExists();

        uint256 balance = _locked[msg.sender].depositAmount;
        delete _locked[msg.sender];
        IERC20(GAIA).transfer(to, balance);
        emit Withdraw(to, msg.sender, balance);
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balanceOfAt(account, block.timestamp);
    }

    function balanceOfAt(address account, uint256 ts) external view returns (uint256) {
        return _balanceOfAt(account, ts);
    }

    function _balanceOfAt(address account, uint256 ts) internal view returns (uint256) {
        if (ts < block.timestamp) revert InvalidTimestamp();

        Locked memory _l = _locked[account];
        unchecked {
            return _l.unlockTime > ts ? _l.depositAmount * (_l.unlockTime - ts) : 0;
        }
    }

    function locked(address account) external view returns (Locked memory) {
        return _locked[account];
    }

    function lockTimeLeft(address account) external view returns (uint256) {
        uint256 unlockTime = _locked[account].unlockTime;
        unchecked {
            return unlockTime > block.timestamp ? unlockTime - block.timestamp : 0;
        }
    }
}

