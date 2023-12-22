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
import "./SignedMath.sol";

import "./IFeeder.sol";
import "./ITrade.sol";
import "./IFees.sol";
import "./IRegistry.sol";
import "./IPriceFeed.sol";
import "./console.sol";
import "./Upgradeable.sol";

// @address:REGISTRY
IRegistry constant registry = IRegistry(0xD4DEa29C068ea13EfA6E4Dd2FADB14aE2353A541);

contract Feeder is Initializable, Upgradeable, IFeeder {

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

    mapping (uint256 => mapping(address => UserPosition)) private userPositions;

    mapping (uint256 => FundHwmData) public fundHwmData;
    mapping (uint256 => uint256) public fundIndentedWithdrawals;
    mapping (uint256 => EnumerableSet.AddressSet) private pendingIndentedWithdrawalUsers;
    uint256 totalAmountOfPendingWithdrawls;

    modifier operatorOnly() {
        require(
            msg.sender == address(registry.interaction()) || msg.sender == address(registry.dripOperator()),
            "F/SNDO"
        ); // sender not a drip operator
        _;
    }

    modifier interactionOnly() {
        require(
            msg.sender == address(registry.interaction()),
            "F/SNI"
        ); // sender not an interaction
        _;
    }

    function initialize() public initializer {
        __Ownable_init();
    }

    function newFund(
        uint256 fundId,
        address manager,
        IToken itoken,
        address trade,
        bool hwm
    ) external override interactionOnly {
        require(funds[fundId].lastPeriod == 0, "F/FE"); // fund exists

        managers[fundId] = manager;
        funds[fundId] = FundInfo({
            lastPeriod: block.number,
            itoken: itoken,
            trade: trade
        });
        fundHwmData[fundId] = FundHwmData({
            hwm: hwm,
            hwmValue: 0
        });

        emit NewFund(fundId, manager);
    }

    // Stake `amount` of USDT and receive IToken proportionally
    function stake(uint256 fundId, address user, uint256 amount) external override interactionOnly returns (uint256 stakedAmount) {
        require(managers[fundId] != address(0x0), "F/FE"); // fund not exists

        IERC20MetadataUpgradeable usdt  = registry.usdt();
        IFees fees = registry.fees();
        usdt.approve(address(fees), amount);
        uint256 left = fees.gatherSf(fundId, amount, address(usdt));

        fundDeposits[fundId] += left;
        addUserPendingDeposit(fundId, user, left);

        if (!EnumerableSet.contains(pendingDepositsUsers[fundId], user)) {
            EnumerableSet.add(pendingDepositsUsers[fundId], user);
        }

        emit Deposit(fundId, user, left);

        return left;
    }

    // Withdraw USDT for IToken `amount`
    function requestWithdrawal(uint256 fundId, address user, uint256 amount, bool indented) external override interactionOnly {
        require(managers[fundId] != address(0x0), "F/FE"); // fund not exists
        require(amount > 0, "F/IA");

        if (indented) {
            addUserIndentedWithdrawals(fundId, user, amount);
        } else {
            addUserPendingWithdrawals(fundId, user, amount);
        }

        emit WithdrawalRequested(fundId, msg.sender, amount);
    }

    function withdraw(uint256 fundId, address user, uint256 totalWithdrawals, uint256 supply, uint256 tradeTvl) internal {
        require(managers[fundId] != address(0x0), "F/FE"); // fund not exists
        (,uint256 withdrawalRequest,) = getUserAccrual(fundId, user);
        uint256 toWithdraw = 0;
        if (withdrawalRequest > 0) {
            toWithdraw = tradeTvl * withdrawalRequest / (totalWithdrawals + supply);
        }
        IERC20MetadataUpgradeable usdt  = registry.usdt();
        require(usdt.balanceOf(address(this)) >= toWithdraw, "F/NEU"); // not enough usdt

        userPositions[fundId][user].totalWithdrawal += toWithdraw;
        pendingAccruals[fundId][user].withdraw = 0;
        EnumerableSet.remove(pendingWithdrawalUsers[fundId], user);

        if (toWithdraw == 0) {
            return;
        }
        require(usdt.transfer(user, toWithdraw), "F/TF"); // transfer failed

        emit Withdrawal(fundId, user, toWithdraw);
    }

    function cancelDeposit(uint256 fundId, address user) external override interactionOnly returns (uint256){
        require(managers[fundId] != address(0x0), "F/FE"); // fund not exists
        (uint256 deposit,,) = getUserAccrual(fundId, user);
        require(deposit > 0, "F/ND"); // no deposit
        IERC20MetadataUpgradeable usdt  = registry.usdt();
        require(usdt.balanceOf(address(this)) >= deposit, "F/NEU"); // not enough usdt
        pendingAccruals[fundId][user].deposit = 0;
        EnumerableSet.remove(pendingDepositsUsers[fundId], user);
        fundDeposits[fundId] -= deposit;

        usdt.transfer(user, deposit);

        emit DepositCancelled(fundId, user, deposit);

        return deposit;
    }

    function cancelWithdrawal(uint256 fundId, address user) external override interactionOnly returns (uint256) {
        require(managers[fundId] != address(0x0), "F/FE"); // fund not exists
        (,uint256 withdrawal, uint256 indentedWithdrawal) = getUserAccrual(fundId, user);
        require(withdrawal > 0, "F/NW"); // no withdrawal

        pendingAccruals[fundId][user].withdraw = 0;
        pendingAccruals[fundId][user].indentedWithdraw = 0;
        EnumerableSet.remove(pendingWithdrawalUsers[fundId], user);
        EnumerableSet.remove(pendingIndentedWithdrawalUsers[fundId], user);
        updateFundWithdrawals(fundId, -int256(withdrawal));
        updateIndentedFundWithdrawals(fundId, -int256(indentedWithdrawal));

        emit WithdrawalCancelled(fundId, user, withdrawal);

        return (withdrawal + indentedWithdrawal);
    }

    function dripUserFunds(uint256 fundId, uint256 tokenSupply, uint256 tradeTvl) internal returns (uint256) {
        address user = EnumerableSet.at(pendingDepositsUsers[fundId], EnumerableSet.length(pendingDepositsUsers[fundId]) - 1);
        uint256 userDeposit = pendingAccruals[fundId][user].deposit;
        pendingAccruals[fundId][user].deposit = 0;
        userPositions[fundId][user].totalDeposit += userDeposit;
        EnumerableSet.remove(pendingDepositsUsers[fundId], user);
        uint256 decimalsDiff = 18 - registry.usdt().decimals() + 1;
        uint256 shares = userDeposit * (10**decimalsDiff); // align to 1e18 and multiply on 10 extra
        if (tokenSupply > 0) {
            shares = userDeposit * (tokenSupply + fundTotalWithdrawals(fundId)) / tradeTvl;
        }
        funds[fundId].itoken.mint(user, shares);

        emit DepositProcessed(fundId, user, userDeposit, shares);
        return userDeposit;
    }

    function updateFundWithdrawals(uint256 fundId, int256 diff) internal {
        fundWithdrawals[fundId] = uint256(int256(fundWithdrawals[fundId]) + diff);
        totalAmountOfPendingWithdrawls = uint256(SignedMath.max(int256(totalAmountOfPendingWithdrawls) + diff, 0));
    }

    function updateIndentedFundWithdrawals(uint256 fundId, int256 diff) internal {
        fundIndentedWithdrawals[fundId] = uint256(int256(fundIndentedWithdrawals[fundId]) + diff);
        totalAmountOfPendingWithdrawls = uint256(SignedMath.max(int256(totalAmountOfPendingWithdrawls) + diff, 0));
    }

    function drip(
        uint256 fundId,
        uint256 subtracted,
        uint256 tokenSupply,
        uint256 tradeTvl,
        uint256 maxBatchSize
    ) external override operatorOnly returns (uint256, uint256) {
        require(managers[fundId] != address(0x0), "F/FE"); // fund not exists

        if (fundDeposits[fundId] <= 0) {
            return (0, 0);
        }
        
        address trader = funds[fundId].trade;
        uint256 pendingDeposits = EnumerableSet.length(pendingDepositsUsers[fundId]);
        uint256 users = pendingDeposits < maxBatchSize ? pendingDeposits : maxBatchSize;
        uint256 depositAmount = 0;
        for (uint256 i = 0; i < users; i++) {
            depositAmount += dripUserFunds(fundId, tokenSupply, tradeTvl);
        }

        require(fundDeposits[fundId] >= depositAmount, "F/LD"); // low deposit
        fundDeposits[fundId] -= depositAmount;
        funds[fundId].lastPeriod = block.number;

        depositAmount = subtracted > depositAmount
            ? 0
            : depositAmount - subtracted;
        if (depositAmount > 0) {
            IERC20Upgradeable(registry.usdt()).safeTransfer(trader, depositAmount);
            emit FundsTransferredToTrader(fundId, trader, depositAmount);
        }
        int256 debtLeft = int256(subtracted) - int256(depositAmount);
        return (users, debtLeft > 0 ? uint256(debtLeft) : 0);
    }

    function gatherFees(uint256 fundId, uint256 tradeTvl, uint256 executionFee) external override operatorOnly {
        uint256 prevHwmValue = fundHwmData[fundId].hwmValue;
        uint256 newHwmValue = this.tokenRate(fundId, tradeTvl);
        IFees fees = registry.fees();
        IERC20MetadataUpgradeable usdt  = registry.usdt();
        if (newHwmValue > prevHwmValue) {
            uint256 pf = fees.calculatePF(fundId, getTvlDiff(fundId, prevHwmValue, newHwmValue));
            usdt.approve(address(fees), pf);
            fees.gatherPf(fundId, getTvlDiff(fundId, prevHwmValue, newHwmValue), address(usdt));
        }
        if (executionFee > 0) {
            usdt.approve(address(fees), executionFee);
            fees.gatherEf(fundId, executionFee, address(usdt));
        }
    }

    function saveHWM(uint256 fundId, uint256 tradeTvl) external override operatorOnly {
        uint256 prevHwmValue = fundHwmData[fundId].hwmValue;
        uint256 newHwmValue = this.tokenRate(fundId, tradeTvl);
        if (!fundHwmData[fundId].hwm || newHwmValue > prevHwmValue) {
            fundHwmData[fundId].hwmValue = newHwmValue;
        }
    }

    // 1 token worth `tokenRate` usdt
    function tokenRate(uint256 fundId, uint256 tradeTvl) external override view returns (uint256) {
        uint256 rate = 0;
        uint256 supply = funds[fundId].itoken.totalSupply() + fundTotalWithdrawals(fundId);
        if (supply != 0 && tradeTvl != 0) {
            rate = tradeTvl * 1e18 / supply;
        }
        return rate;
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
        if (!EnumerableSet.contains(pendingWithdrawalUsers[fundId], user)) {
            EnumerableSet.add(pendingWithdrawalUsers[fundId], user);
        }
        updateFundWithdrawals(fundId, int256(amount));
    }

    function addUserIndentedWithdrawals(uint256 fundId, address user, uint256 amount) internal {
        UserAccruals storage acc = pendingAccruals[fundId][user];
        acc.indentedWithdraw += amount;
        if (!EnumerableSet.contains(pendingIndentedWithdrawalUsers[fundId], user)) {
            EnumerableSet.add(pendingIndentedWithdrawalUsers[fundId], user);
        }
        updateIndentedFundWithdrawals(fundId, int256(amount));
    }

    function getFund(uint256 fundId) public view override returns (FundInfo memory) {
        return funds[fundId];
    }

    // @dev Pending user balance on feeder contract
    // @return pending deposit amount(usdt), pending withdraw amount(tokens)
    function getUserAccrual(uint256 fundId, address user) public view override returns (uint256, uint256, uint256) {
        return (
            pendingAccruals[fundId][user].deposit,
            pendingAccruals[fundId][user].withdraw,
            pendingAccruals[fundId][user].indentedWithdraw
        );
    }

    // @dev Pending user balance on feeder contract
    // @return total deposit(USDT), total withdrawal(USDT), tokenAmount, pendingWithdrawals tokens
    function getUserData(uint256 fundId, address user) external view override returns (uint256, uint256, uint256, uint256) {
        return (
            userPositions[fundId][user].totalDeposit,
            userPositions[fundId][user].totalWithdrawal,
            funds[fundId].itoken.balanceOf(user),
            pendingAccruals[fundId][user].withdraw + pendingAccruals[fundId][user].indentedWithdraw
        );
    }

    // @dev Returns pending amounts to withdraw (unindented) and deposit for the current reporting period
    // @return to deposit (USDT), to withdraw (USDT), pf (USDT)
    function pendingTvl(uint256 fundId, uint256 tradeTvl) external override view returns (uint256, uint256, uint256) {
        uint256 totalWithdrawals = fundTotalWithdrawals(fundId);
        uint256 supply = funds[fundId].itoken.totalSupply() + totalWithdrawals;
        uint256 pf = this.calculatePf(fundId, tradeTvl);

        uint256 pendingWithdrawal = 0;
        if (supply > 0 && fundWithdrawals[fundId] != 0) {
            pendingWithdrawal = fundWithdrawals[fundId] * (tradeTvl - pf) / supply;
        }

        return (fundDeposits[fundId], pendingWithdrawal, pf);
    }

    function withdrawMultiple(
        uint256 fundId,
        uint256 supply,
        uint256 toWithdraw,
        uint256 tradeTvl,
        uint256 maxBatchSize
    ) external override operatorOnly returns (uint256) {
        uint256 totalWithdrawals = 0;
        uint256 users = EnumerableSet.length(pendingWithdrawalUsers[fundId]) < maxBatchSize
            ? EnumerableSet.length(pendingWithdrawalUsers[fundId])
            : maxBatchSize;
        for (uint256 i = 0; i < users; i++) {
            address user = EnumerableSet.at(pendingWithdrawalUsers[fundId], EnumerableSet.length(pendingWithdrawalUsers[fundId]) - 1);
            (,uint256 withdrawalRequest,) = getUserAccrual(fundId, user);
            totalWithdrawals += withdrawalRequest;
            withdraw(fundId, user, toWithdraw, supply, tradeTvl);
        }
        updateFundWithdrawals(fundId, -int256(totalWithdrawals));
        return users;
    }

    function moveIndentedWithdrawals(uint256 fundId, uint256 maxBatchSize) external override operatorOnly returns (uint256) {
        uint256 users = EnumerableSet.length(pendingIndentedWithdrawalUsers[fundId]) < maxBatchSize
            ? EnumerableSet.length(pendingIndentedWithdrawalUsers[fundId])
            : maxBatchSize;
        for (uint256 i = 0; i < users; i++) {
            address user = EnumerableSet.at(pendingIndentedWithdrawalUsers[fundId], 0);
            uint256 amount = pendingAccruals[fundId][user].indentedWithdraw;
            pendingAccruals[fundId][user].indentedWithdraw = 0;
            addUserPendingWithdrawals(fundId, user, amount);
            updateIndentedFundWithdrawals(fundId, -int256(amount));
            EnumerableSet.remove(pendingIndentedWithdrawalUsers[fundId], user);
        }
        return EnumerableSet.length(pendingIndentedWithdrawalUsers[fundId]);
    }

    function transferFromTrade(uint256 fundId, uint256 amount) external override operatorOnly {
        ITrade(funds[fundId].trade).transferToFeeder(uint256(amount));
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
            pf = registry.fees().calculatePF(fundId, getTvlDiff(fundId, prevHwmValue, newHwmValue));
        }
        return pf;
    }

    function fundTotalWithdrawals(uint256 fundId) public override view returns (uint256) {
        return fundWithdrawals[fundId] + fundIndentedWithdrawals[fundId];
    }

    function getTvlDiff(uint256 fundId, uint256 prevRate, uint256 newRate) private view returns (uint256) {
        uint256 supply = funds[fundId].itoken.totalSupply() + fundTotalWithdrawals(fundId);
        if (supply == 0) {
            return 0;
        }
        uint256 prevTvl = supply * prevRate / 1e18;
        uint256 newTvl = supply * newRate / 1e18;
        return newTvl - prevTvl;
    }

    function hasUnprocessedWithdrawals() public view returns (bool) {
        return totalAmountOfPendingWithdrawls > 0;
	}

    function getPendingOperationsCount(uint256 fundId) public override view returns (uint256) {
        return EnumerableSet.length(pendingDepositsUsers[fundId]) +
            EnumerableSet.length(pendingWithdrawalUsers[fundId]) +
            EnumerableSet.length(pendingIndentedWithdrawalUsers[fundId]);
    }

    function getPendingExecutionFee(uint256 fundId, uint256 tradeTvl, uint256 gasPrice) public override view returns (uint256) {
        uint256 executionFee = 0;
        IPriceFeed ethPriceFeed = registry.ethPriceFeed();
        if (tradeTvl > 0 || fundDeposits[fundId] > 0) {
            uint256 _gasPrice = gasPrice;
            if (gasPrice == 0) {
                _gasPrice = tx.gasprice;
            }
            executionFee = DRIP_GAS_USAGE * _gasPrice
                / 10**uint256(ethPriceFeed.decimals())
                * 10**(registry.usdt()).decimals()
                * uint256(ethPriceFeed.latestAnswer())
                * (getPendingOperationsCount(fundId) / MAX_USERS_PER_BATCH + 1)
                / 10**18;
            if (executionFee > tradeTvl + fundDeposits[fundId]) {
                // if we can't gather executionFee from fund, let's pay ourselves
                // also we avoid this case by just not calling drip for empty funds
                executionFee = 0;
            }
        }
        return executionFee;
    }
}

