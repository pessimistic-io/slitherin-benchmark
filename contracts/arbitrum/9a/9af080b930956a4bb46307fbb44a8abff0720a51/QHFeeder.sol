// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./SafeERC20Upgradeable.sol";
import "./SafeMath.sol";
import "./EnumerableSet.sol";
import "./IERC20.sol";

import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./OwnableUpgradeable.sol";

import "./Math.sol";
import "./IFeeder.sol";
import "./IFees.sol";

import "./WardedUpgradeable.sol";

contract QHFeeder is Initializable, UUPSUpgradeable, OwnableUpgradeable, WardedUpgradeable, IFeeder {

    using SafeERC20Upgradeable for IERC20Upgradeable;
    using EnumerableSet for EnumerableSet.AddressSet;

    mapping (uint256 => EnumerableSet.AddressSet) private pendingWithdrawalUsers;
    mapping (uint256 => EnumerableSet.AddressSet) private pendingDepositsUsers;

    // never interact with this directly
    // fundId => user => accrual
    mapping (uint256 => mapping(address => UserAccruals)) private pendingAccruals;

    mapping (uint256 => address) public managers;

    mapping (uint256 => uint256) public fundDeposits;
    // fundId => token amount
    mapping (uint256 => uint256) public fundWithdrawals;

    mapping (uint256 => FundInfo) public funds;

    IERC20Upgradeable public _usdtToken;
    IFees public fees;
    mapping (uint256 => mapping(address => UserPosition)) private userPositions;

    function initialize(address usdt_, address fees_) public initializer {
        __Ownable_init();
        __Warded_init();

        _usdtToken = IERC20Upgradeable(usdt_);
        _usdtToken.approve(fees_, type(uint256).max);
        fees = IFees(fees_);
    }

    function setInvestToken(address _newToken) external onlyOwner {
        _usdtToken = IERC20Upgradeable(_newToken);
        _usdtToken.approve(address(fees), type(uint256).max);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function newFund(uint256 fundId,
        address manager,
        uint256 minStakingAmount,
        uint256 minWithdrawalAmount,
        IToken itoken
    ) external override auth {
        require(funds[fundId].lastPeriod == 0, "QHFeeder/fund-exists");

        managers[fundId] = manager;
        funds[fundId] = FundInfo({
            minDeposit: minStakingAmount,
            minWithdrawal: minWithdrawalAmount,
            lastPeriod: block.number,
            itoken: itoken
        });

        emit NewFund(fundId, manager);
    }

    function setFees(address fees_) external onlyOwner {
        require(fees_ != address(0), "QHFeeder/invalid-fees");
        fees = IFees(fees_);
        _usdtToken.approve(fees_, type(uint256).max);

        emit FeesChanged(fees_);
    }

    // Stake `amount` of USDT and receive IToken proportionally
    function stake(uint256 fundId, address user, uint256 amount) external override auth returns (uint256 stakedAmount) {
        require(managers[fundId] != address(0x0), "QHFeeder/fund-not-init");

        uint256 left = fees.gatherSf(fundId, amount, address(_usdtToken));

        fundDeposits[fundId] += left;
        addUserPendingDeposit(fundId, user, left);

        if (!EnumerableSet.contains(pendingDepositsUsers[fundId], user)) {
            EnumerableSet.add(pendingDepositsUsers[fundId], user);
        }

        emit Deposit(fundId, user, left);

        return left;
    }

    // Withdraw USDT for IToken `amount`
    function requestWithdrawal(uint256 fundId, address user, uint256 amount) external override auth {
        require(managers[fundId] != address(0x0), "QHFeeder/fund-not-init");
        require(amount > 0, "F/IA");
        // if user has pending invest
//        if (getUserAccrual(fundId, user) > 0) {
//            uint256 depo = amount;
            // if user wants to withdraw more than pending amount
//            if (amount > uint256(getUserAccrual(fundId, user))) {
//                depo = uint256(getUserAccrual(fundId, user));
//            }
//
//            amountOut -= depo;
//        }

        addUserPendingWithdrawals(fundId, user, amount);
        fundWithdrawals[fundId] += amount;

        if (!EnumerableSet.contains(pendingWithdrawalUsers[fundId], user)) {
            EnumerableSet.add(pendingWithdrawalUsers[fundId], user);
        }

        emit WithdrawalRequested(fundId, msg.sender, amount);
    }

    function withdraw(uint256 fundId, address user, uint256 tradeTvl) public override auth {
        require(managers[fundId] != address(0x0), "QHFeeder/fund-not-init");
        (,uint256 withdrawalRequest) = getUserAccrual(fundId, user);
        require(withdrawalRequest > 0, "QHFeeder/no-debt");

        uint256 toWithdraw = tradeTvl *  withdrawalRequest / (withdrawalRequest + funds[fundId].itoken.totalSupply());
        require(_usdtToken.balanceOf(address(this)) >= toWithdraw, "QHFeeder/not-enough-usdt");

        userPositions[fundId][user].totalWithdrawal += toWithdraw;
        pendingAccruals[fundId][user].withdraw = 0;
        EnumerableSet.remove(pendingWithdrawalUsers[fundId], user);
        fundWithdrawals[fundId] -= withdrawalRequest;

        require(_usdtToken.transfer(user, toWithdraw), "QHFeeder/transfer-failed");

        emit Withdrawal(fundId, user, toWithdraw);
    }

    function cancelDeposit(uint256 fundId, address user) external override auth returns (uint256){
        require(managers[fundId] != address(0x0), "QHFeeder/fund-not-init");
        (uint256 deposit,) = getUserAccrual(fundId, user);
        require(deposit > 0, "QHFeeder/no-deposit");

        require(_usdtToken.balanceOf(address(this)) >= deposit, "QHFeeder/not-enough-usdt");
        pendingAccruals[fundId][user].deposit = 0;
        EnumerableSet.remove(pendingDepositsUsers[fundId], user);
        fundDeposits[fundId] -= deposit;

        _usdtToken.transfer(user, deposit);

        emit DepositCancelled(fundId, user, deposit);

        return deposit;
    }

    function cancelWithdrawal(uint256 fundId, address user) external override auth returns (uint256) {
        require(managers[fundId] != address(0x0), "QHFeeder/fund-not-init");
        (,uint256 withdrawal) = getUserAccrual(fundId, user);
        require(withdrawal > 0, "QHFeeder/no-withdrawal");

        pendingAccruals[fundId][user].withdraw = 0;
        EnumerableSet.remove(pendingWithdrawalUsers[fundId], user);
        fundWithdrawals[fundId] -= withdrawal;

        emit WithdrawalCancelled(fundId, user, withdrawal);

        return withdrawal;
    }

    uint256 constant public MAX_USERS_PER_BATCH = 20;

    function dripUserFunds(
        uint256 fundId,
        uint256 userIndex,
        uint256 tokenSupply,
        uint256 tradeTvl
    ) internal returns (uint256) {
        if (userIndex >= EnumerableSet.length(pendingDepositsUsers[fundId])) {
            return 0;
        }
        address user = EnumerableSet.at(pendingDepositsUsers[fundId], userIndex);
        uint256 userDeposit = pendingAccruals[fundId][user].deposit;
        pendingAccruals[fundId][user].deposit = 0;
        userPositions[fundId][user].totalDeposit += userDeposit;
        EnumerableSet.remove(pendingDepositsUsers[fundId], user);

        uint256 shares = userDeposit * 1e13; // align to 1e18 and multiply on 10 extra
        if (tokenSupply > 0) {
            shares = userDeposit * tokenSupply / tradeTvl;
        }
        funds[fundId].itoken.mint(user, shares);

        emit DepositProcessed(fundId, user, userDeposit, shares);
        return userDeposit;
    }

    function drip(uint256 fundId, address trader, uint256 tradeTvl) external override auth {
        require(managers[fundId] != address(0x0), "QHFeeder/fund-not-init");
        require(fundDeposits[fundId] > 0, "QHFeeder/feeder-empty");

        uint256 users = MAX_USERS_PER_BATCH;
        if (EnumerableSet.length(pendingDepositsUsers[fundId]) < users) {
            users = EnumerableSet.length(pendingDepositsUsers[fundId]);
        }

        uint256 depositAmount = 0;
        uint256 tokenSupply = funds[fundId].itoken.totalSupply();

        for (uint256 i = 0; i < users; i++) {
            depositAmount += dripUserFunds(fundId, i, tokenSupply, tradeTvl);
        }

        require(fundDeposits[fundId] >= depositAmount, "QHFeeder/low-deposits");
        fundDeposits[fundId] -= depositAmount;
        funds[fundId].lastPeriod = block.number;

        _usdtToken.safeTransfer(trader, depositAmount);

        emit FundsTransferredToTrader(fundId, trader, depositAmount);
    }

    // @dev Pending user balance on feeder contract
    // positive means user wants to invest, negative — withdraw
    function addUserPendingDeposit(uint256 fundId, address user, uint256 amount) internal returns(uint256) {
        UserAccruals storage acc = pendingAccruals[fundId][user];

        if (acc.block < funds[fundId].lastPeriod) {
            acc.deposit = 0;
        }

        acc.deposit += amount;
        acc.block = block.number;
        return acc.deposit;
    }

    // @dev Pending user balance on feeder contract
    // positive means user wants to invest, negative — withdraw
    function addUserPendingWithdrawals(uint256 fundId, address user, uint256 amount) internal returns(uint256) {
        UserAccruals storage acc = pendingAccruals[fundId][user];

        if (acc.block < funds[fundId].lastPeriod) {
            acc.withdraw = 0;
        }

        acc.withdraw += amount;
        acc.block = block.number;
        return acc.withdraw;
    }

    // @dev Pending user balance on feeder contract
    // @return pending deposit amount(usdt), pending withdraw amount(tokens)
    function getUserAccrual(uint256 fundId, address user) public view override returns (uint256, uint256) {
        if (pendingAccruals[fundId][user].block < funds[fundId].lastPeriod) {
            return (0, 0);
        }
        return (pendingAccruals[fundId][user].deposit, pendingAccruals[fundId][user].withdraw);
    }

    // @dev Pending user balance on feeder contract
    // @return total deposit(USDT), total withdrawal(USDT), tokenAmount, pendingWithdrawals tokens
    function getUserData(uint256 fundId, address user) external view override returns (uint256, uint256, uint256, uint256) {
        return (
            userPositions[fundId][user].totalDeposit,
            userPositions[fundId][user].totalWithdrawal,
            funds[fundId].itoken.balanceOf(user),
            pendingAccruals[fundId][user].withdraw
        );
    }

    function withdrawMultiple(uint256 fundId, address[] calldata users, uint256 tradeTvl) external override auth {
        for (uint256 i = 0; i < users.length; i++) {
            withdraw(fundId, users[i], tradeTvl);
        }
    }

    function userWaitingForWithdrawal(uint256 fundId) external override view returns(address[] memory) {
        return EnumerableSet.values(pendingWithdrawalUsers[fundId]);
    }

    function userWaitingForDeposit(uint256 fundId) external override view returns(address[] memory) {
        return EnumerableSet.values(pendingDepositsUsers[fundId]);
    }

    // @dev Returns difference between deposit and withdrawal requests in USDT
    // Positive value means that there more deposits than withdrawals
    // Negative otherwise
    function tvl(uint256 fundId, uint256 tradeTVL) external override view returns (int256) {
        uint256 supply = funds[fundId].itoken.totalSupply() + fundWithdrawals[fundId];
        uint256 pendingWithdrawal = 0;
        if (supply > 0) {
            pendingWithdrawal = fundWithdrawals[fundId] * tradeTVL / supply;
        }
        return int256(fundDeposits[fundId]) - int256(pendingWithdrawal);
    }

    // DEBUG // FIXME

    function removePendingWithdrawalUser(uint256 fundId, address user) external {
        EnumerableSet.remove(pendingWithdrawalUsers[fundId], user);
    }
}

