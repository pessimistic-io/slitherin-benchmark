// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "./AssetStore.sol";
import "./DataStore.sol";
import "./FundStore.sol";
import "./PoolStore.sol";
import "./Roles.sol";

/**
 * @title  Pool
 * @notice Users can deposit supported assets to back trader profits and receive
 *         a share of trader losses. Each asset pool is siloed, e.g. the ETH
 *         pool is independent from the USDC pool.
 */
contract Pool is Roles {
    // Constants
    uint256 public constant BPS_DIVIDER = 10000;

    // Events
    event PoolDeposit(
        address indexed user,
        address indexed asset,
        uint256 amount,
        uint256 clpAmount,
        uint256 poolBalance
    );

    event PoolWithdrawal(
        address indexed user,
        address indexed asset,
        uint256 amount,
        uint256 feeAmount,
        uint256 clpAmount,
        uint256 poolBalance
    );

    event PoolPayIn(
        address indexed user,
        address indexed asset,
        string market,
        uint256 amount,
        uint256 bufferToPoolAmount,
        uint256 poolBalance,
        uint256 bufferBalance
    );

    event PoolPayOut(
        address indexed user,
        address indexed asset,
        string market,
        uint256 amount,
        uint256 poolBalance,
        uint256 bufferBalance
    );

    // Contracts
    DataStore public DS;

    AssetStore public assetStore;
    FundStore public fundStore;
    PoolStore public poolStore;

    /// @dev Initializes DataStore address
    constructor(RoleStore rs, DataStore ds) Roles(rs) {
        DS = ds;
    }

    /// @notice Initializes protocol contracts
    /// @dev Only callable by governance
    function link() external onlyGov {
        assetStore = AssetStore(DS.getAddress('AssetStore'));
        fundStore = FundStore(payable(DS.getAddress('FundStore')));
        poolStore = PoolStore(DS.getAddress('PoolStore'));
    }

    /// @notice Credit trader loss to buffer and pay pool from buffer amount based on time and payout rate
    /// @param user User which incurred trading loss
    /// @param asset Asset address, e.g. address(0) for ETH
    /// @param market Market, e.g. "ETH-USD"
    /// @param amount Amount of trader loss
    function creditTraderLoss(address user, address asset, string memory market, uint256 amount) external onlyContract {
        // credit trader loss to buffer
        poolStore.incrementBufferBalance(asset, amount);

        // local variables
        uint256 lastPaid = poolStore.getLastPaid(asset);
        uint256 _now = block.timestamp;
        uint256 amountToSendPool;

        if (lastPaid == 0) {
            // during the very first execution, set lastPaid and return
            poolStore.setLastPaid(asset, _now);
        } else {
            // get buffer balance and buffer payout period to calculate amountToSendPool
            uint256 bufferBalance = poolStore.getBufferBalance(asset);
            uint256 bufferPayoutPeriod = poolStore.bufferPayoutPeriod();

            // Stream buffer balance progressively into the pool
            amountToSendPool = (bufferBalance * (block.timestamp - lastPaid)) / bufferPayoutPeriod;
            if (amountToSendPool > bufferBalance) amountToSendPool = bufferBalance;

            // update storage
            poolStore.incrementBalance(asset, amountToSendPool);
            poolStore.decrementBufferBalance(asset, amountToSendPool);
            poolStore.setLastPaid(asset, _now);
        }

        // emit event
        emit PoolPayIn(
            user,
            asset,
            market,
            amount,
            amountToSendPool,
            poolStore.getBalance(asset),
            poolStore.getBufferBalance(asset)
        );
    }

    /// @notice Pay out trader profit, from buffer first then pool if buffer is depleted
    /// @param user Address to send funds to
    /// @param asset Asset address, e.g. address(0) for ETH
    /// @param market Market, e.g. "ETH-USD"
    /// @param amount Amount of trader profit
    function debitTraderProfit(
        address user,
        address asset,
        string calldata market,
        uint256 amount
    ) external onlyContract {
        // return if profit = 0
        if (amount == 0) return;

        uint256 bufferBalance = poolStore.getBufferBalance(asset);

        // decrement buffer balance first
        poolStore.decrementBufferBalance(asset, amount);

        // if amount is greater than available in the buffer, pay remaining from the pool
        if (amount > bufferBalance) {
            uint256 diffToPayFromPool = amount - bufferBalance;
            uint256 poolBalance = poolStore.getBalance(asset);
            require(diffToPayFromPool < poolBalance, '!pool-balance');
            poolStore.decrementBalance(asset, diffToPayFromPool);
        }

        // transfer profit out
        fundStore.transferOut(asset, user, amount);

        // emit event
        emit PoolPayOut(user, asset, market, amount, poolStore.getBalance(asset), poolStore.getBufferBalance(asset));
    }

    /// @notice Deposit 'amount' of 'asset' into the pool
    /// @param asset Asset address, e.g. address(0) for ETH
    /// @param amount Amount to be deposited
    function deposit(address asset, uint256 amount) public payable {
        require(amount > 0, '!amount');
        require(assetStore.isSupported(asset), '!asset');

        uint256 balance = poolStore.getBalance(asset);
        address user = msg.sender;

        // if asset is ETH (address(0)), set amount to msg.value
        if (asset == address(0)) {
            amount = msg.value;
            fundStore.transferIn{value: amount}(asset, user, amount);
        } else {
            fundStore.transferIn(asset, user, amount);
        }

        // pool share is equal to pool balance of user divided by the total balance
        uint256 clpSupply = poolStore.getClpSupply(asset);
        uint256 clpAmount = balance == 0 || clpSupply == 0 ? amount : (amount * clpSupply) / balance;

        // increment balances
        poolStore.incrementUserClpBalance(asset, user, clpAmount);
        poolStore.incrementBalance(asset, amount);

        // emit event
        emit PoolDeposit(user, asset, amount, clpAmount, poolStore.getBalance(asset));
    }

    /// @notice Withdraw 'amount' of 'asset'
    /// @param asset Asset address, e.g. address(0) for ETH
    /// @param amount Amount to be withdrawn
    function withdraw(address asset, uint256 amount) public {
        require(amount > BPS_DIVIDER, '!amount');
        require(assetStore.isSupported(asset), '!asset');

        address user = msg.sender;

        // check pool balance and clp supply
        uint256 balance = poolStore.getBalance(asset);
        uint256 clpSupply = poolStore.getClpSupply(asset);
        require(balance > 0 && clpSupply > 0, '!empty');

        // check user balance
        uint256 userBalance = poolStore.getUserBalance(asset, user);
        if (amount > userBalance) amount = userBalance;

        // calculate pool withdrawal fee
        uint256 feeAmount = (amount * poolStore.getWithdrawalFee(asset)) / BPS_DIVIDER;
        uint256 amountMinusFee = amount - feeAmount;

        // CLP amount
        uint256 clpAmount = (amount * clpSupply) / balance;

        // decrement balances
        poolStore.decrementUserClpBalance(asset, user, clpAmount);
        poolStore.decrementBalance(asset, amountMinusFee);

        // transfer funds out
        fundStore.transferOut(asset, user, amountMinusFee);

        // emit event
        emit PoolWithdrawal(user, asset, amount, feeAmount, clpAmount, poolStore.getBalance(asset));
    }
}

