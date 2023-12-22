//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import "./SafeMathUpgradeable.sol";
import "./IERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./AddressUpgradeable.sol";
import "./Initializable.sol";
import "./CoreRefUpgradeable.sol";
import "./ITrancheYieldCurve.sol";
import "./IMasterPoints.sol";
import "./IStrategyToken.sol";
import "./IFeeRewards.sol";
import "./IWETH.sol";
import "./IFarmTokenPool.sol";

contract TrancheMasterPerpetualUpgradeable is Initializable, CoreRefUpgradeable, ReentrancyGuardUpgradeable {
    using SafeMathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    struct TrancheParams {
        uint256 fee;
        bool principalFee;
    }

    struct Tranche {
        uint256 principal;
        uint256 autoPrincipal;
        uint256 validPercent; // do we need this
        uint256 fee;
        uint256 autoValid;
        bool principalFee;
    }

    struct TrancheSnapshot {
        uint256 principal;
        uint256 capital;
        uint256 validPercent;
        uint256 rate;
        uint256 fee;
        uint256 startAt;
        uint256 stopAt;
    }

    struct Investment {
        uint256 cycle;
        uint256 principal;
    }

    struct UserInfo {
        uint256 balance;
        bool isAuto;
    }

    uint256 private PERCENTAGE_PARAM_SCALE;
    uint256 public PERCENTAGE_SCALE;
    uint256 private MAX_FEE;
    uint256 public pendingStrategyWithdrawal;
    uint256 public producedFee;
    uint256 public duration;
    uint256 public investmentWindow;
    uint256 public cycle;
    uint256 public actualStartAt;
    bool public active;
    Tranche[] public tranches;
    address public wNative;
    address public currency;
    address[] public farmTokens;
    address public farmTokensPool;
    address public staker;
    address public strategy;
    address public trancheYieldCurve;
    address public devAddress;
    address[] private zeroAddressArr;
    address[] public userInvestPendingAddressArr;

    mapping(address => UserInfo) public userInfo;
    // userAddress => tid => pendingAmount
    mapping(address => mapping(uint256 => uint256)) public userInvestPending;
    mapping(address => mapping(uint256 => Investment)) public userInvest;

    // cycle => trancheID => snapshot
    mapping(uint256 => mapping(uint256 => TrancheSnapshot)) public trancheSnapshots;

    event Deposit(address account, uint256 amount);

    event Invest(address account, uint256 tid, uint256 cycle, uint256 amount);

    event Redeem(address account, uint256 tid, uint256 cycle, uint256 amount);

    event Withdraw(address account, uint256 amount);

    event Harvest(address account, uint256 tid, uint256 cycle, uint256 principal, uint256 capital);

    event TrancheAdd(uint256 tid, uint256 fee, bool principalFee);

    event TrancheUpdated(uint256 tid, uint256 fee, bool principalFee);

    event TrancheStart(uint256 tid, uint256 cycle, uint256 principal);

    event TrancheSettle(uint256 tid, uint256 cycle, uint256 principal, uint256 capital, uint256 rate);

    // Error Code
    // E1 = tranches is incomplete
    // E2 = invalid tranche id
    // E3 = not active
    // E4 = already active
    // E5 = user autorolling
    // E6 = at least 1 strategy is pending for withdrawal
    // E7 = currency is not wNative
    // E8 = value != msg.value
    // E9 = invalid fee
    // E10 = cannot switch ON autoroll while the cycle is active
    // E11 = invalid amountIn
    // E12 = invalid amountInvest
    // E13 = balance not enough
    // E14 = invalid amount
    // E15 = not enough principal
    // E16 = nothing for redemption
    // E17 = MUST be 2 tranches
    // E18 = cycle not expired
    // E19 = no strategy is pending for withdrawal
    // E20 = not enough balance for fee
    // E21 = investmentWindow is missed
    // E22 = both tranches should have positive principal/autoprincipal
    // E23 = a new cycle can be started only after investment window completed
    // E24 = invalid investmentWindow

    modifier checkActive() {
        require(active, "E3");
        _;
    }

    modifier checkNotActive() {
        require(!active, "E4");
        _;
    }

    modifier checkNotAuto() {
        require(!userInfo[msg.sender].isAuto, "E5");
        _;
    }

    modifier checkNoPendingStrategyWithdrawal() {
        require(pendingStrategyWithdrawal == 0, "E6");
        _;
    }

    function transferTokenToVault(uint256 value) internal {
        if (msg.value != 0) {
            require(currency == wNative, "E7");
            require(value == msg.value, "E8");
            IWETH(currency).deposit{value: msg.value}();
        } else {
            IERC20Upgradeable(currency).safeTransferFrom(msg.sender, address(this), value);
        }
    }

    function init(
        address[] memory _coreAndWNative,
        address _currency,
        address[] memory _farmTokens,
        address _farmTokensPool,
        address _strategy,
        address _staker,
        address _devAddress,
        uint256 _duration,
        uint256 _investmentWindow,
        TrancheParams[] memory _params
    ) public initializer {
        CoreRefUpgradeable.initialize(_coreAndWNative[0]);
        ReentrancyGuardUpgradeable.__ReentrancyGuard_init();
        wNative = _coreAndWNative[1];
        currency = _currency;
        farmTokens = _farmTokens;
        farmTokensPool = _farmTokensPool;
        strategy = _strategy;
        staker = _staker;
        devAddress = _devAddress;
        duration = _duration;
        investmentWindow = _investmentWindow;
        PERCENTAGE_PARAM_SCALE = 1e5;
        PERCENTAGE_SCALE = 1e18;
        MAX_FEE = 50000;
        pendingStrategyWithdrawal = 0;

        IERC20Upgradeable(currency).safeApprove(strategy, type(uint256).max);

        for (uint256 i = 0; i < _params.length; i++) {
            _add(_params[i].fee, _params[i].principalFee);
        }
        zeroAddressArr.push(address(0));
    }

    function _add(uint256 fee, bool principalFee) internal {
        require(fee <= MAX_FEE, "E9");
        tranches.push(
            Tranche({
                fee: fee,
                principal: 0,
                autoPrincipal: 0,
                validPercent: 0,
                autoValid: 0,
                principalFee: principalFee
            })
        );
        emit TrancheAdd(tranches.length - 1, fee, principalFee);
    }

    function set(uint256 tid, uint256 fee, bool principalFee) public onlyTimelock {
        require(fee <= MAX_FEE, "E9");
        tranches[tid].fee = fee;
        tranches[tid].principalFee = principalFee;
        emit TrancheUpdated(tid, fee, principalFee);
    }

    // Updating invest

    function _updateInvest(address account) internal {
        UserInfo storage u = userInfo[account];
        uint256 initPrincipal;
        uint256 principal;
        uint256 capital;
        for (uint i = 0; i < tranches.length; i++) {
            Investment storage inv = userInvest[account][i];
            initPrincipal = inv.principal;
            principal = inv.principal;
            // check principal. If it's zero then set the user's latest invest cycle to the current invest cycle
            if (principal == 0) {
                inv.cycle = cycle;
                continue;
            }
            if (u.isAuto) {
                for (uint j = inv.cycle; j < cycle; j++) {
                    TrancheSnapshot memory snapshot = trancheSnapshots[j][i];
                    capital = principal.mul(snapshot.rate).div(PERCENTAGE_SCALE);
                    emit Harvest(account, i, j, principal, capital);
                    principal = capital;
                }
                inv.principal = principal;
                IMasterPoints(staker).updateStake(i, account, inv.principal);
            } else {
                if (inv.cycle < cycle) {
                    // after queueing withdrawal the funds no longer participate in the cycle
                    TrancheSnapshot memory snapshot = trancheSnapshots[inv.cycle][i];
                    capital = principal.mul(snapshot.rate).div(PERCENTAGE_SCALE);
                    u.balance = u.balance.add(capital);
                    inv.principal = 0;
                    IMasterPoints(staker).updateStake(i, account, 0);
                    emit Harvest(account, i, inv.cycle, principal, capital);
                }
            }
            inv.cycle = cycle;
            // update farm token pools with user principal
            for (uint256 s = 0; s < farmTokens.length; s++) {
                if (initPrincipal < inv.principal) {
                    IFarmTokenPool(farmTokensPool).stake(farmTokens[s], i, account, inv.principal.sub(initPrincipal));
                } else if (initPrincipal > inv.principal) {
                    IFarmTokenPool(farmTokensPool).unstake(farmTokens[s], i, account, initPrincipal.sub(inv.principal));
                }
            }
        }
    }

    function queueWithdrawal() public nonReentrant {
        _switchAuto(false, msg.sender);
    }

    function _switchAuto(bool _auto, address userAddress) internal {
        _updateInvest(userAddress);
        if (_auto) {
            require(active == false, "E10");
        }
        UserInfo storage u = userInfo[userAddress];
        if (u.isAuto == _auto) {
            return;
        }

        for (uint i = 0; i < tranches.length; i++) {
            Investment memory inv = userInvest[userAddress][i];
            if (inv.principal == 0) {
                continue;
            }
            Tranche storage t = tranches[i];
            if (_auto) {
                t.principal = t.principal.sub(inv.principal);
                t.autoPrincipal = t.autoPrincipal.add(inv.principal);
            } else {
                t.principal = t.principal.add(inv.principal);
                t.autoPrincipal = t.autoPrincipal.sub(inv.principal);
                // here we basically subtract inv.principal from autoValid so that on the next cycle the contract knows
                // that user asked for funds withdrawal and subtract them from autoPrincipal
                if (active) {
                    t.autoValid = t.autoValid > inv.principal ? t.autoValid.sub(inv.principal) : 0; // make sure it's compatible with startCycle autoValid logic
                }
            }
        }
        u.isAuto = _auto;
    }

    function investDirect(
        uint256 amountIn,
        uint256 tid,
        uint256 amountInvest
    ) public payable checkNotActive checkNoPendingStrategyWithdrawal nonReentrant {
        // ensure that the investment is within investment window
        if (cycle > 0) {
            TrancheSnapshot memory snapshot = trancheSnapshots[cycle - 1][0];
            require(block.timestamp.sub(snapshot.stopAt) <= investmentWindow, "E21");
        }
        _updateInvest(msg.sender);
        transferTokenToVault(amountIn);
        require(amountIn > 0, "E11");
        require(amountInvest > 0, "E12");

        UserInfo storage u = userInfo[msg.sender];
        require(u.balance.add(amountIn) >= amountInvest, "E13");

        u.balance = u.balance.add(amountIn);
        emit Deposit(msg.sender, amountIn);

        _invest(tid, amountInvest, msg.sender);
        _switchAuto(true, msg.sender);
    }

    function _invest(uint256 tid, uint256 amount, address userAddress) private {
        UserInfo storage u = userInfo[userAddress];
        require(amount <= u.balance, "E13");

        Tranche storage t = tranches[tid];
        Investment storage inv = userInvest[userAddress][tid];
        inv.principal = inv.principal.add(amount);
        u.balance = u.balance.sub(amount);
        if (u.isAuto) {
            t.autoPrincipal = t.autoPrincipal.add(amount); // make sure this logic is compatible with the _invest -> _switchAuto sequence in the public function triggering _invest
        } else {
            t.principal = t.principal.add(amount);
        }
        IMasterPoints(staker).updateStake(tid, userAddress, inv.principal);

        // update farm token pools with user amount invested
        for (uint256 s = 0; s < farmTokens.length; s++) {
            IFarmTokenPool(farmTokensPool).stake(farmTokens[s], tid, userAddress, amount);
        }
        emit Invest(userAddress, tid, cycle, amount);
    }

    function _redeem(uint256 tid) private returns (uint256) {
        UserInfo storage u = userInfo[msg.sender];
        Investment storage inv = userInvest[msg.sender][tid];
        uint256 principal = inv.principal;

        Tranche storage t = tranches[tid];
        u.balance = u.balance.add(principal);
        t.principal = t.principal.sub(principal);

        IMasterPoints(staker).updateStake(tid, msg.sender, 0);
        inv.principal = 0;
        emit Redeem(msg.sender, tid, cycle, principal);
        return principal;
    }

    function redeemDirect() public checkNotActive checkNotAuto nonReentrant {
        _updateInvest(msg.sender);
        for (uint256 i = 0; i < tranches.length; i++) {
            uint256 amount = _redeem(i);
            UserInfo storage u = userInfo[msg.sender];
            u.balance = u.balance.sub(amount);
            _safeUnwrap(msg.sender, amount);
            emit Withdraw(msg.sender, amount);
        }
    }

    function redeemDirectPartial(uint256 tid) public checkNotActive checkNotAuto nonReentrant {
        _updateInvest(msg.sender);
        uint256 amount = _redeem(tid);
        UserInfo storage u = userInfo[msg.sender];
        u.balance = u.balance.sub(amount);
        _safeUnwrap(msg.sender, amount);
        emit Withdraw(msg.sender, amount);
    }

    function withdraw(uint256 amount) public nonReentrant {
        _updateInvest(msg.sender); // here if the auto=false the updateInvest adds investment to balance so we can withdraw
        require(amount > 0, "E14");
        UserInfo storage u = userInfo[msg.sender];
        require(amount <= u.balance, "E13");
        u.balance = u.balance.sub(amount);
        _safeUnwrap(msg.sender, amount);
        emit Withdraw(msg.sender, amount);
    }

    function start() public checkNoPendingStrategyWithdrawal {
        if (cycle > 0) {
            TrancheSnapshot memory snapshot = trancheSnapshots[cycle - 1][0];
            require(block.timestamp >= snapshot.stopAt.add(investmentWindow), "E23");
        }
        _startCycle();
    }

    function _startCycle() internal checkNotActive {
        for (uint256 i = 0; i < tranches.length; i++) {
            require(tranches[i].principal.add(tranches[i].autoPrincipal) >= 0, "E22");
        }
        uint256 total = 0;
        for (uint256 i = 0; i < tranches.length; i++) {
            Tranche memory t = tranches[i];
            total = total.add(t.principal).add(t.autoPrincipal);
        }
        IStrategyToken(strategy).deposit(total);
        actualStartAt = block.timestamp;
        active = true;
        for (uint256 i = 0; i < tranches.length; i++) {
            Tranche storage t = tranches[i];
            t.autoValid = t.principal == 0 ? t.principal.add(t.autoPrincipal) : t.autoPrincipal;
            emit TrancheStart(i, cycle, t.principal.add(t.autoPrincipal));
        }
        IMasterPoints(staker).start(block.number.add(duration.div(3)));
    }

    function _stopCycle(address[] memory _strategyAddresses) internal {
        _processExit(_strategyAddresses);
        active = false;
        cycle++;
        IMasterPoints(staker).next(cycle);
    }

    struct ProcessExitVariables {
        uint256 totalPrincipal;
        uint256 totalYield;
        uint256 seniorYield;
        uint256 seniorYieldDistribution;
        uint256 seniorProportion;
        uint256 seniorIndex;
        uint256 juniorIndex;
    }

    function withdrawFromStrategy(
        address[] memory _strategyAddresses
    ) internal returns (uint256 totalWant, uint256[] memory afterFarmTokens) {
        uint256 beforeWant = IERC20Upgradeable(currency).balanceOf(address(this)); // dont need to touch aacum fees
        afterFarmTokens = new uint256[](farmTokens.length);
        IStrategyToken(strategy).withdraw(_strategyAddresses);
        totalWant = IERC20Upgradeable(currency).balanceOf(address(this)).sub(beforeWant);
        for (uint256 i = 0; i < farmTokens.length; i++) {
            afterFarmTokens[i] = IERC20Upgradeable(farmTokens[i]).balanceOf((address(this)));
        }
    }

    function _calculateExchangeRate(
        uint256 current,
        uint256 base,
        uint256 percentage_scale
    ) internal pure returns (uint256) {
        if (current == base) {
            return percentage_scale;
        } else if (current > base) {
            return percentage_scale.add((current - base).mul(percentage_scale).div(base));
        } else {
            return percentage_scale.sub((base - current).mul(percentage_scale).div(base));
        }
    }

    function _processExit(address[] memory _strategyAddresses) internal {
        require(tranches.length == 2, "E17");

        (uint256 total, uint256[] memory farmTokensAmts) = withdrawFromStrategy(_strategyAddresses);
        uint256 restCapital = total; // total is the amount of currency after withdrawal
        uint256 cycleExchangeRate;
        uint256 capital;
        uint256 principal;
        uint256 shortage;

        ProcessExitVariables memory p;
        ITrancheYieldCurve.YieldDistrib memory y;
        p.seniorIndex = 0;
        Tranche storage senior = tranches[p.seniorIndex];
        p.juniorIndex = tranches.length - 1;
        Tranche storage junior = tranches[p.juniorIndex];
        p.totalPrincipal = senior.principal.add(senior.autoPrincipal).add(junior.principal).add(junior.autoPrincipal);
        if (restCapital >= p.totalPrincipal) {
            p.totalYield = restCapital.sub(p.totalPrincipal);
        } else {
            p.totalYield = 0;
        }

        // senior
        principal = senior.principal + senior.autoPrincipal;
        capital = 0;
        p.seniorProportion = principal.mul(PERCENTAGE_SCALE).div(p.totalPrincipal);

        y = ITrancheYieldCurve(trancheYieldCurve).getYieldDistribution(
            p.seniorProportion,
            p.totalPrincipal,
            restCapital,
            duration,
            farmTokensAmts
        );

        p.seniorYield = y.fixedSeniorYield;

        if (p.seniorYield > p.totalYield) {
            shortage = p.seniorYield.sub(p.totalYield);
            shortage = shortage < junior.principal.add(junior.autoPrincipal)
                ? shortage
                : junior.principal.add(junior.autoPrincipal); // we dont' need to leave positive amount in junior because autorestart of cycles is not enabled
        }

        uint256 all = principal.add(p.seniorYield);
        bool satisfied = restCapital >= all;

        // If restCapital >= senior principal + seniorYield we just subtract this senior volume from restCapital.
        if (!satisfied) {
            capital = restCapital;
            restCapital = 0;
        } else {
            capital = all;
            restCapital = restCapital.sub(all); // this is now can be distributed to junior tranche
        }

        uint256 fee;
        // here we take the fee on the capital (principal + yield)
        if (senior.principalFee) {
            fee = satisfied ? capital.mul(senior.fee).div(PERCENTAGE_PARAM_SCALE) : 0;
        } else if (capital > principal) {
            // here we take fee on the yield only
            fee = (capital.sub(principal)).mul(senior.fee).div(PERCENTAGE_PARAM_SCALE);
        }
        if (fee > 0) {
            producedFee = producedFee.add(fee);
            capital = capital.sub(fee);
        }

        cycleExchangeRate = _calculateExchangeRate(capital, principal, PERCENTAGE_SCALE);

        trancheSnapshots[cycle][p.seniorIndex] = TrancheSnapshot({
            principal: principal,
            capital: capital,
            validPercent: senior.validPercent,
            rate: cycleExchangeRate,
            fee: senior.fee,
            startAt: actualStartAt,
            stopAt: block.timestamp
        });

        senior.principal = 0;

        senior.autoPrincipal = senior.autoValid.mul(cycleExchangeRate).div(PERCENTAGE_SCALE).add(
            senior.autoPrincipal > senior.autoValid ? senior.autoPrincipal.sub(senior.autoValid) : 0
        );

        emit TrancheSettle(p.seniorIndex, cycle, principal, capital, cycleExchangeRate);

        principal = junior.principal + junior.autoPrincipal;
        capital = restCapital;
        if (p.seniorYield > p.totalYield) {
            if (capital >= shortage) {
                capital = capital.sub(shortage);
            } else {
                capital = 0;
            }
        }
        if (junior.principalFee && capital != 0) {
            // apply principal fee only if capital !=0 after paying senior
            fee = capital.mul(junior.fee).div(PERCENTAGE_PARAM_SCALE);
        } else if (capital > principal && shortage == 0) {
            fee = capital.sub(principal).mul(junior.fee).div(PERCENTAGE_PARAM_SCALE);
        } // apply fee only if junior shortage is  zero
        if (fee > 0) {
            producedFee = producedFee.add(fee);
            capital = capital.sub(fee);
        }
        cycleExchangeRate = _calculateExchangeRate(capital, principal, PERCENTAGE_SCALE);
        trancheSnapshots[cycle][p.juniorIndex] = TrancheSnapshot({
            principal: principal,
            capital: capital,
            validPercent: junior.validPercent,
            rate: cycleExchangeRate,
            fee: junior.fee,
            startAt: actualStartAt,
            stopAt: block.timestamp
        });

        junior.principal = 0;
        junior.autoPrincipal = junior.autoValid.mul(cycleExchangeRate).div(PERCENTAGE_SCALE).add(
            junior.autoPrincipal > junior.autoValid ? junior.autoPrincipal.sub(junior.autoValid) : 0
        );

        // send tokens to the farm rewards contract
        for (uint256 t = 0; t < farmTokens.length; t++) {
            IERC20Upgradeable(farmTokens[t]).approve(farmTokensPool, y.seniorFarmYield[t].add(y.juniorFarmYield[t]));
            IFarmTokenPool(farmTokensPool).sendRewards(farmTokens[t], 0, y.seniorFarmYield[t]);
            IFarmTokenPool(farmTokensPool).sendRewards(farmTokens[t], 1, y.juniorFarmYield[t]);
        }
        emit TrancheSettle(p.juniorIndex, cycle, principal, capital, cycleExchangeRate);
    }

    function stop() public checkActive nonReentrant {
        require(block.timestamp >= actualStartAt + duration, "E18");
        _stopCycle(zeroAddressArr);
    }

    function balanceOf(address account) external view returns (uint256 balance, uint256 invested) {
        UserInfo memory u = userInfo[account];
        uint256 capital;
        uint256 principal;
        balance = u.balance;
        for (uint i = 0; i < tranches.length; i++) {
            Investment memory inv = userInvest[account][i];
            principal = inv.principal;
            if (principal == 0) {
                continue;
            }
            if (u.isAuto) {
                for (uint j = inv.cycle; j < cycle; j++) {
                    TrancheSnapshot memory snapshot = trancheSnapshots[j][i];
                    capital = principal.mul(snapshot.rate).div(PERCENTAGE_SCALE);
                    principal = capital;
                }
            } else {
                if (inv.cycle < cycle) {
                    TrancheSnapshot memory snapshot = trancheSnapshots[inv.cycle][i];
                    capital = principal.mul(snapshot.rate).div(PERCENTAGE_SCALE);
                    principal = capital;
                }
            }
            invested = invested.add(principal);
        }
    }

    /************ Admin functions ****************/

    function setDuration(uint256 _duration) public onlyGovernor {
        duration = _duration;
    }

    function setDevAddress(address _devAddress) public onlyGovernor {
        devAddress = _devAddress;
    }

    function setInvestmentWindow(uint256 _window) public onlyGovernor {
        require(investmentWindow > 0, "E24");
        investmentWindow = _window;
    }

    function stopAndUpdateStrategiesAndRatios(
        address[] calldata _strategies,
        uint256[] calldata _ratios,
        address[] calldata toAdd,
        address[] calldata toPause,
        address[] calldata newTokens
    ) public checkActive nonReentrant onlyTimelock {
        require(block.timestamp >= actualStartAt + duration, "E18");
        _stopCycle(zeroAddressArr);
        IFarmTokenPool(farmTokensPool).changeRewardTokens(toAdd, toPause, newTokens);
        farmTokens = newTokens;
        IMultiStrategyToken(strategy).updateStrategiesAndRatios(_strategies, _ratios);
    }

    function emergencyStop(address[] memory _strategyAddresses) public checkActive nonReentrant onlyGovernor {
        pendingStrategyWithdrawal = IMultiStrategyToken(strategy).strategyCount() - _strategyAddresses.length;
        _stopCycle(_strategyAddresses);
    }

    function recoverFund(address[] memory _strategyAddresses) public checkNotActive nonReentrant onlyGovernor {
        require(pendingStrategyWithdrawal > 0, "E19");
        pendingStrategyWithdrawal -= _strategyAddresses.length;
        uint256 before = IERC20Upgradeable(currency).balanceOf(address(this));
        IStrategyToken(strategy).withdraw(_strategyAddresses);
        uint256 total = IERC20Upgradeable(currency).balanceOf(address(this)).sub(before);
        _safeUnwrap(devAddress, total);
    }

    function setStaker(address _staker) public onlyGovernor {
        staker = _staker;
    }

    function setStrategy(address _strategy) public onlyGovernor {
        strategy = _strategy;
    }

    function setTrancheYieldCurve(address _trancheYieldCurve) public onlyGovernor {
        trancheYieldCurve = _trancheYieldCurve;
    }

    function withdrawFee(uint256 amount) public {
        require(amount <= producedFee, "E20");
        producedFee = producedFee.sub(amount);
        if (devAddress != address(0)) {
            _safeUnwrap(devAddress, amount);
        }
    }

    function transferFeeToStaking(uint256 _amount, address _pool) public onlyGovernor {
        require(_amount > 0, "E14");
        IERC20Upgradeable(currency).safeApprove(_pool, _amount);
        IFeeRewards(_pool).sendRewards(_amount);
    }

    function _safeUnwrap(address to, uint256 amount) internal {
        if (currency == wNative) {
            IWETH(currency).withdraw(amount);
            AddressUpgradeable.sendValue(payable(to), amount);
        } else {
            IERC20Upgradeable(currency).safeTransfer(to, amount);
        }
    }

    receive() external payable {}
}

