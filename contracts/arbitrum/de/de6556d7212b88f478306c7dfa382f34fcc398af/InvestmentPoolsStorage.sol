// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "./InvestmentPoolsInterface.sol";

abstract contract InvestmentPoolsStorage is InvestmentPoolsInterface {
    uint256 public totalPools;

    uint256 public protocolFeePercentage;

    address public dmpNftContractAddress;

    address public tokenSaleContractAddress;

    address public paymentTokenAddress;

    address public feeTokenAddress;

    address public protocolFeeReceiver;

    mapping(address => bool) public controller;

    mapping(address => bool) public bannedUsersMapping;

    mapping(uint256 => uint256) public creatorFeePerPool;

    mapping(uint256 => uint256) public tournamentEntryFeePerPoolId;

    mapping(uint256 => mapping(address => uint256)) public userBalancePerPool;

    mapping(address => mapping(uint256 => bool))
        public userHaveInvestedInPoolId;

    mapping(uint256 => InvestorsPerPool[]) public investorsPerPoolId;

    mapping(address => string) public profileDescription;

    mapping(address => string) public profilePicture;

    struct InvestorsPerPool {
        address user;
        uint256 amount;
    }

    Investments[] public investments;

    struct Investments {
        address user;
        uint256 amount;
        uint256 poolId;
    }

    Pools[] public pools;

    struct Pools {
        address creator;
        uint256 targetAmount;
        uint256 amountRaised;
        uint256 endTimestamp;
        uint256 poolId;
        uint256 markUp;
        string tournamentType;
        string description;
        bool claimed;
        bool canceled;
        bool validated;
        bool rejected;
    }

    /// @dev Events
    event InvestmentPoolCreated(
        address account,
        uint256 poolId,
        uint256 amount,
        uint256 createdTimestamp,
        uint256 endTimestamp,
        string description
    );

    event PoolClaimed(
        address account,
        uint256 poolId,
        uint256 amountRaised,
        uint256 claimedTimetamp
    );

    event PoolCanceled(
        address account,
        uint256 poolId,
        uint256 feeReturned,
        uint256 canceledTimetamp
    );

    event PoolInvestment (
        address account,
        uint256 poolId,
        uint256 amountInvested,
        uint256 investmentTimetamp
    );

    mapping(uint256 => mapping(address => bool)) public userRemovedInvestmentFromPoolId;
}

