// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {IERC20} from "./IERC20.sol";

struct StrategyParams {
    uint256 activation;
    uint256 debtRatio;
    uint256 totalDebt;
    uint256 totalGain;
    uint256 totalLoss;
    uint256 lastReport;
    uint256 performanceFee;
    address strategist;
}

struct WithdrawRequest {
    address author;
    address user;
    uint256 shares;
    uint256 maxLoss;
    uint256 expected;
    bool success;
    uint256 timestamp;
}

struct WithdrawEpoch {
    WithdrawRequest[] requests;
    bool inProgress;
    uint256 approveExpected;
    uint256 approveActual;
}

interface IVault {
    error InsufficientFunds(uint256 amount, uint256 balance);

    event SgReceived(address indexed token, uint256 amount, address sender);
    event StrategyWithdrawnSome(
        uint16 indexed chainId,
        address indexed strategy,
        uint256 amount,
        uint256 loss,
        uint256 id
    );
    event FulfilledWithdrawEpoch(uint256 epochId, uint256 requestCount);
    event StrategyReported(
        uint16 chainId,
        address strategy,
        uint256 gain,
        uint256 loss,
        uint256 debtPaid,
        uint256 totalGain,
        uint256 totalLoss,
        uint256 totalDebt,
        uint256 debtAdded,
        uint256 debtRatio,
        uint256 tokens
    );

    function initialize(
        address _governance,
        address _lzEndpoint,
        IERC20 _token,
        address _sgRouter
    ) external;

    function token() external view returns (IERC20);

    function revokeFunds() external;

    function totalAssets() external view returns (uint256);

    function deposit(
        uint256 _amount,
        address _recipient
    ) external returns (uint256);

    function withdraw(
        uint256 _maxShares,
        address _recipient,
        uint256 _maxLoss
    ) external;

    function addStrategy(
        uint16 _chainId,
        address _strategy,
        uint256 _debtRatio,
        uint256 _performanceFee,
        address _strategist
    ) external;

    function handleWithdrawals() external;

    function pricePerShare() external view returns (uint256);

    function revokeStrategy(uint16 _chainId, address _strategy) external;

    function updateStrategyDebtRatio(
        uint16 _chainId,
        address _strategy,
        uint256 _debtRatio
    ) external;

    function governance() external view returns (address);
}

