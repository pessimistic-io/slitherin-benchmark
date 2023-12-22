// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "./MatrixVault.sol";

contract RadiantMatrixVault is MatrixVault {
    uint256 public lockPeriod = 7 days;
    mapping(address => uint256) public depositTime;
    event LockPeriodUpdated(uint256 _oldLockPeriod, uint256 _lockPeriod);

    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _approvalDelay
    ) MatrixVault(_name, _symbol, _approvalDelay) {}

    modifier isNotLocked(address _user) {
        require(
            block.timestamp >= depositTime[_user] + lockPeriod,
            "withdraw-time-has-not-passed"
        );
        _;
    }

    function deposit(uint256 _amount) public override nonReentrant {
        depositTime[msg.sender] = block.timestamp;
        _deposit(_amount);
    }

    function withdraw(uint256 _amount)
        public
        override
        isNotLocked(msg.sender)
        nonReentrant
    {
        _withdraw(_amount);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override isNotLocked(from) {}

    function updateLockPeriod(uint256 _lockPeriod) external onlyOwner {
        require(
            _lockPeriod > 1 days,
            "lock-period-must-be-gt-1-day"
        );
        require(
            _lockPeriod <= 30 days,
            "lock-period-must-be-lt-1-month"
        );
        emit LockPeriodUpdated(lockPeriod, _lockPeriod);
        lockPeriod = _lockPeriod;
    }
}

