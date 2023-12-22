// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./SafeERC20.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./OwnableUpgradeable.sol";

contract VotingUpgradeable is OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    struct VoterParams {
        uint balance;
        uint lockTimestamp;
    }

    IERC20 public gh2O;

    mapping(address => VoterParams) public voterParams;

    bool public isEmergency;
    uint public lockTimeframe;

    event VoterBalanceIncreased(address voter, uint amount, uint lock);
    event VoterBalanceDecreased(address voter, uint amount);

    event EmergencyModeSet(bool isEmergency);
    event LockTimeframeSet(uint lockTimeframe);

    function initialize(address _gh2O) public initializer {
        __Ownable_init();
        __ReentrancyGuard_init();

        gh2O = IERC20(_gh2O);
        lockTimeframe = 1 weeks;
    }

    modifier notEmergency() {
        require(!isEmergency, "Emergency");
        _;
    }

    function balanceOf(address holder) external view returns (uint256) {
        return voterParams[holder].balance;
    }

    function addVotes(uint amount) external nonReentrant notEmergency {
        require(gh2O.balanceOf(_msgSender()) >= amount, "Insufficient balance");

        gh2O.safeTransferFrom(_msgSender(), address(this), amount);

        voterParams[_msgSender()].balance += amount;
        voterParams[_msgSender()].lockTimestamp =
            block.timestamp +
            lockTimeframe;

        emit VoterBalanceIncreased(
            _msgSender(),
            amount,
            voterParams[_msgSender()].lockTimestamp
        );
    }

    function removeVotes(uint amount) external nonReentrant notEmergency {
        require(
            voterParams[_msgSender()].balance >= amount,
            "Insufficient amount"
        );
        require(
            voterParams[_msgSender()].lockTimestamp < block.timestamp,
            "Lock active"
        );
        require(
            gh2O.balanceOf(address(this)) >= amount,
            "Insufficient contract balance"
        );

        gh2O.safeTransfer(_msgSender(), amount);

        voterParams[_msgSender()].balance -= amount;

        emit VoterBalanceDecreased(_msgSender(), amount);
    }

    function emergencyWithdraw(
        address token,
        address to,
        uint amount
    ) external onlyOwner {
        require(isEmergency, "Not allowed");

        IERC20(token).safeTransfer(to, amount);
    }

    function adjustVoterParams(
        address voter,
        uint balance,
        uint lock
    ) external nonReentrant onlyOwner {
        require(isEmergency, "Not allowed");

        voterParams[voter].balance = balance;
        voterParams[voter].lockTimestamp = lock;
    }

    function setLockTimeframe(uint newTimeframe) external onlyOwner {
        lockTimeframe = newTimeframe;

        emit LockTimeframeSet(newTimeframe);
    }

    function setGH2O(address _gh2O) external onlyOwner {
        gh2O = IERC20(_gh2O);
    }

    function setEmergency(bool _isEmergency) external onlyOwner {
        isEmergency = _isEmergency;

        emit EmergencyModeSet(isEmergency);
    }
}

