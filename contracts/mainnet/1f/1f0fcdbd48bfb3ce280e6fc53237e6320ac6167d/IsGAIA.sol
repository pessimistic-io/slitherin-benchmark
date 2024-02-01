// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IsGAIA {
    event Deposit(address indexed to, address indexed from, uint256 amount, uint256 unlockTime, uint256 ts);
    event Slope(address indexed to, uint256 currentAmount, uint256 currentUnlockTime);
    event Withdraw(address indexed to, address indexed caller, uint256 amount);

    error AddressZero();
    error BothParamsZero();
    error NewAmountZero();
    error DurationZero();
    error ExceedMaxDuration(uint256 newUnlockTime);
    error NotAvailableYet(uint256 timeLeft);
    error InvalidTimestamp();
    error AddressToShouldBeMsgSender();
    error NoDepositExists();

    struct Locked {
        uint128 depositAmount;
        uint128 unlockTime;
    }

    function GAIA() external view returns (address);

    function MAX_DURATION() external view returns (uint256);

    function deposit(
        address to,
        uint256 amount,
        uint256 duration
    ) external;

    function depositWithPermit(
        address to,
        uint256 amount,
        uint256 duration,
        uint256 deadline,
        bytes32 r,
        bytes32 s,
        uint8 v
    ) external;

    function withdraw(address to) external;

    function balanceOf(address account) external view returns (uint256);

    function balanceOfAt(address account, uint256 ts) external view returns (uint256);

    function locked(address account) external view returns (Locked memory);

    function lockTimeLeft(address account) external view returns (uint256);
}

