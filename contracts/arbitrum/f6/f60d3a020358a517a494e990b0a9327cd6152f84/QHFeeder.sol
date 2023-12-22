// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./SafeERC20Upgradeable.sol";
import "./SafeMath.sol";
import "./EnumerableSet.sol";
import "./IERC20.sol";
import "./IERC20MetadataUpgradeable.sol";

import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./OwnableUpgradeable.sol";

import "./Math.sol";
import "./IFeeder.sol";
import "./ITrade.sol";
import "./IFees.sol";

import "./WardedUpgradeable.sol";
import "./console.sol";

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

    mapping (uint256 => FundHwmData) public fundHwmData;
    uint256 _initialRate;
    uint256 _usdcDecimals;

    function initialize(address usdt_, address fees_) public initializer {
        __Ownable_init();
        __Warded_init();

        _usdtToken = IERC20Upgradeable(usdt_);
        _usdtToken.approve(fees_, type(uint256).max);
        fees = IFees(fees_);
        _usdcDecimals = IERC20MetadataUpgradeable(usdt_).decimals();
        _initialRate = 10**(_usdcDecimals - 1);
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
        IToken itoken,
        address trade,
        bool hwm
    ) external override auth {
        require(funds[fundId].lastPeriod == 0, "QHFeeder/fund-exists");

        managers[fundId] = manager;
        funds[fundId] = FundInfo({
            minDeposit: minStakingAmount,
            minWithdrawal: minWithdrawalAmount,
            lastPeriod: block.number,
            itoken: itoken,
            trade: trade
        });
        fundHwmData[fundId] = FundHwmData({
            hwm: hwm,
            hwmValue: _initialRate
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

        addUserPendingWithdrawals(fundId, user, amount);
        fundWithdrawals[fundId] += amount;

        if (!EnumerableSet.contains(pendingWithdrawalUsers[fundId], user)) {
            EnumerableSet.add(pendingWithdrawalUsers[fundId], user);
        }

        emit WithdrawalRequested(fundId, msg.sender, amount);
    }

    function withdraw(uint256 fundId, address user, uint256 supply, uint256 pf, uint256 tradeTvl) internal auth {
        require(managers[fundId] != address(0x0), "QHFeeder/fund-not-init");
        (,uint256 withdrawalRequest) = getUserAccrual(fundId, user);
        require(withdrawalRequest > 0, "QHFeeder/no-debt");

        uint256 toWithdraw = (tradeTvl - pf) * withdrawalRequest / (fundWithdrawals[fundId] + supply);
        require(_usdtToken.balanceOf(address(this)) >= toWithdraw, "QHFeeder/not-enough-usdt");

        userPositions[fundId][user].totalWithdrawal += toWithdraw;
        pendingAccruals[fundId][user].withdraw = 0;
        EnumerableSet.remove(pendingWithdrawalUsers[fundId], user);

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

    function dripUserFunds(uint256 fundId, uint256 tokenSupply, uint256 tradeTvl) internal returns (uint256) {
        address user = EnumerableSet.at(pendingDepositsUsers[fundId], 0);
        uint256 userDeposit = pendingAccruals[fundId][user].deposit;
        pendingAccruals[fundId][user].deposit = 0;
        userPositions[fundId][user].totalDeposit += userDeposit;
        EnumerableSet.remove(pendingDepositsUsers[fundId], user);

        uint256 decimalsDiff = 18 - _usdcDecimals + 1;
        uint256 shares = userDeposit * (10**decimalsDiff); // align to 1e18 and multiply on 10 extra
        if (tokenSupply > 0) {
            shares = userDeposit * tokenSupply / tradeTvl;
        }
        funds[fundId].itoken.mint(user, shares);

        emit DepositProcessed(fundId, user, userDeposit, shares);
        return userDeposit;
    }

    uint256 constant public MAX_USERS_PER_BATCH = 20;
    function drip(uint256 fundId, address trader, uint256 subtracted, uint256 tradeTvl) external override auth {
        require(managers[fundId] != address(0x0), "QHFeeder/fund-not-init");

        if (fundDeposits[fundId] <= 0) {
            return;
        }

        uint256 users = MAX_USERS_PER_BATCH;
        if (EnumerableSet.length(pendingDepositsUsers[fundId]) < users) {
            users = EnumerableSet.length(pendingDepositsUsers[fundId]);
        }

        uint256 depositAmount = 0;
        uint256 tokenSupply = funds[fundId].itoken.totalSupply() + fundWithdrawals[fundId];
        for (uint256 i = 0; i < users; i++) {
            depositAmount += dripUserFunds(fundId, tokenSupply, tradeTvl);
        }

        require(fundDeposits[fundId] >= depositAmount, "QHFeeder/low-deposits");
        fundDeposits[fundId] -= depositAmount;
        funds[fundId].lastPeriod = block.number;

        require(subtracted < depositAmount, "QHFeeder/cant-pay-from-stakes");
        depositAmount -= subtracted;
        _usdtToken.safeTransfer(trader, depositAmount);

        emit FundsTransferredToTrader(fundId, trader, depositAmount);
    }

    function gatherPF(uint256 fundId, uint256 tradeTvl) external override auth {
        uint256 prevHwmValue = fundHwmData[fundId].hwmValue;
        uint256 newHwmValue = this.tokenRate(fundId, tradeTvl);
        if (newHwmValue > prevHwmValue) {
            fundHwmData[fundId].hwmValue = newHwmValue;
            fees.gatherPf(fundId, getTvlDiff(fundId, prevHwmValue, newHwmValue), address(_usdtToken));
        }
        if (!fundHwmData[fundId].hwm) {
            fundHwmData[fundId].hwmValue = newHwmValue;
        }
    }

    // 1 token worth `tokenRate` usdt
    function tokenRate(uint256 fundId, uint256 tradeTvl) external override view returns (uint256) {
        uint rate = _initialRate;
        uint supply = funds[fundId].itoken.totalSupply() + fundWithdrawals[fundId];
        if (supply != 0 && tradeTvl != 0) {
            rate = tradeTvl * 1e18 / supply;
        }
        return rate;
    }

    function getInvestToken() external override view returns(address) {
        return address(_usdtToken);
    }

    function hwmValue(uint256 fundId) external override view returns (uint256) {
        return fundHwmData[fundId].hwmValue;
    }

    function addUserPendingDeposit(uint256 fundId, address user, uint256 amount) internal {
        UserAccruals storage acc = pendingAccruals[fundId][user];
        acc.deposit += amount;
    }

    function addUserPendingWithdrawals(uint256 fundId, address user, uint256 amount) internal {
        UserAccruals storage acc = pendingAccruals[fundId][user];
        acc.withdraw += amount;
    }

    // @dev Pending user balance on feeder contract
    // @return pending deposit amount(usdt), pending withdraw amount(tokens)
    function getUserAccrual(uint256 fundId, address user) public view override returns (uint256, uint256) {
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

    // @dev Returns pending amounts to withdraw and deposit for the current reporting period
    // @return to deposit (USDT), to withdraw (USDT), pf (USDT)
    function pendingTvl(uint256 fundId, uint256 tradeTvl) external override view returns (uint256, uint256, uint256) {
        uint256 supply = funds[fundId].itoken.totalSupply() + fundWithdrawals[fundId];
        uint256 pf = this.calculatePf(fundId, tradeTvl);

        uint256 pendingWithdrawal = 0;
        if (supply > 0 && fundWithdrawals[fundId] != 0) {
            pendingWithdrawal = fundWithdrawals[fundId] * (tradeTvl - pf) / supply;
        }

        return (fundDeposits[fundId], pendingWithdrawal, pf);
    }

    function withdrawMultiple(
        uint256 fundId,
        address[] calldata users,
        uint256 supply,
        uint256 pf,
        uint256 tradeTvl
    ) external override auth {
        uint256 totalWithdrawals = 0;
        for (uint256 i = 0; i < users.length; i++) {
            (,uint256 withdrawalRequest) = getUserAccrual(fundId, users[i]);
            totalWithdrawals += withdrawalRequest;
            withdraw(fundId, users[i], supply, pf, tradeTvl);
        }
        fundWithdrawals[fundId] -= totalWithdrawals;
    }

    function userWaitingForWithdrawal(uint256 fundId) external override view returns(address[] memory) {
        return EnumerableSet.values(pendingWithdrawalUsers[fundId]);
    }

    function userWaitingForDeposit(uint256 fundId) external override view returns(address[] memory) {
        return EnumerableSet.values(pendingDepositsUsers[fundId]);
    }

    function calculatePf(uint256 fundId, uint256 tradeTvl) external override view returns (uint256) {
        uint256 pf = 0;
        uint256 prevHwmValue = fundHwmData[fundId].hwmValue;
        uint256 newHwmValue = this.tokenRate(fundId, tradeTvl);
        if (newHwmValue > prevHwmValue) {
            pf = fees.calculatePF(fundId, getTvlDiff(fundId, prevHwmValue, newHwmValue));
        }
        return pf;
    }

    function getTvlDiff(uint256 fundId, uint256 prevRate, uint256 newRate) private view returns (uint256) {
        uint256 supply = funds[fundId].itoken.totalSupply() + fundWithdrawals[fundId];
        if (supply == 0) {
            return 0;
        }
        uint256 prevTvl = supply * prevRate / 1e18;
        uint256 newTvl = supply * newRate / 1e18;
        return newTvl - prevTvl;
    }
}

