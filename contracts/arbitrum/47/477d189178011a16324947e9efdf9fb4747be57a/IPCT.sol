// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;
pragma abicoder v2;

interface IPCT {
    struct Pool {
        // account -> fxToken -> Deposit
        mapping(address => mapping(address => Deposit)) deposits;
        // Protocol interface address => whether protocol is valid
        mapping(address => bool) protocolInterfaces;
        // Protocol interface address => invested amount
        mapping(address => uint256) protocolInvestments;
        // Deposits that are either flagged (not confirmed) or confirmed and not invested.
        uint256 totalDeposits;
        // Total deposit amount during last investment round, including invested amount.
        uint256 totalDepositsAtInvestment;
        // Amount of deposits that have been invested (<= totalDepositsAtInvestment).
        uint256 totalInvestments;
        // Total accrued interest from investments.
        uint256 totalAccrued;
        // Current pool reward ratio over total deposits.
        uint256 S;
        // Current investment round number.
        uint256 N;
    }

    struct Deposit {
        uint256 amount_flagged;
        uint256 amount_confirmed;
        uint256 S;
        uint256 N;
    }

    event Stake(
        address indexed account,
        address indexed fxToken,
        address indexed collateralToken,
        uint256 amount
    );

    event Unstake(
        address indexed account,
        address indexed fxToken,
        address indexed collateralToken,
        uint256 amount
    );

    event ClaimInterest(
        address indexed acount,
        address indexed collateralToken,
        uint256 amount
    );

    event SetProtocolInterface(
        address indexed protocolInterfaceAddress,
        address indexed collateralToken
    );

    event UnsetProtocolInterface(
        address indexed protocolInterfaceAddress,
        address indexed collateralToken
    );

    event ProtocolClaimInterest(
        address indexed protocolInterfaceAddress,
        address indexed collateralToken,
        uint256 amount
    );

    event ProtocolReturnFunds(
        address indexed protocolInterfaceAddress,
        address indexed collateralToken,
        uint256 amount
    );

    event ProtocolDepositFunds(
        address indexed protocolInterfaceAddress,
        address indexed collateralToken,
        uint256 amount
    );

    function stake(
        address account,
        uint256 amount,
        address fxToken,
        address collateralToken
    ) external returns (uint256 errorCode);

    function unstake(
        address account,
        uint256 amount,
        address fxToken,
        address collateralToken
    ) external returns (uint256 errorCode);

    function claimInterest(address fxToken, address collateralToken) external;

    function setProtocolInterface(
        address collateralToken,
        address protocolInterfaceAddress
    ) external;

    function unsetProtocolInterface(
        address collateralToken,
        address protocolInterfaceAddress
    ) external;

    function claimProtocolInterest(
        address collateralToken,
        address protocolInterfaceAddress
    ) external;

    function depositProtocolFunds(
        address collateralToken,
        address protocolInterfaceAddress,
        uint256 ratio
    ) external;

    function withdrawProtocolFunds(
        address collateralToken,
        address protocolInterfaceAddress,
        uint256 amount
    ) external;

    function requestTreasuryFunds(
        address collateralToken,
        address requestedToken,
        uint256 amount
    ) external;

    function returnTreasuryFunds(
        address collateralToken,
        address returnedToken,
        uint256 amount
    ) external;

    function setProtocolFee(uint256 ratio) external;

    function protocolFee() external view returns (uint256);

    function balanceOfStake(
        address account,
        address fxToken,
        address collateralToken
    ) external view returns (uint256 amount);

    function balanceOfClaimableInterest(
        address account,
        address fxToken,
        address collateralToken
    ) external view returns (uint256 amount);

    function getTotalDeposits(address collateralToken)
        external
        view
        returns (uint256 amount);

    function getTotalInvestments(address collateralToken)
        external
        view
        returns (uint256 amount);

    function getProtocolInvestments(
        address collateralToken,
        address protocolInterfaceAddress
    ) external view returns (uint256 amount);

    function getTotalAccruedInterest(address collateralToken)
        external
        view
        returns (uint256 amount);
}

