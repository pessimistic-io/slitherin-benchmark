// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC20.sol";

import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./IERC20MetadataUpgradeable.sol";

import "./InvestPeriod.sol";
import "./IFeeder.sol";
import "./IFees.sol";
import "./ITrade.sol";
import "./IInteraction.sol";
import "./IRegistry.sol";
import "./FundState.sol";
import "./IDripOperator.sol";
import "./IUpgrader.sol";
import "./ITradeParamsUpdater.sol";

import "./Upgradeable.sol";
import "./console.sol";

// @address:REGISTRY
IRegistry constant registry = IRegistry(0x5517dB2A5C94B3ae95D3e2ec12a6EF86aD5db1a5);

contract Interaction is Upgradeable, IInteraction {
    uint256 public periodLength;
    mapping (uint256 => FundInfo) public funds;
    // Fund Id => amount
    mapping (uint256 => uint256) public deposits;
    mapping (uint256 => uint256) public withdrawals;
    InvestPeriod investPeriodUtils;

    function initialize(address _investPeriodUtils) public initializer {
        __Ownable_init();
        investPeriodUtils = InvestPeriod(_investPeriodUtils);
    }

    modifier noDripInProgress(uint256 fundId) {
        require(!registry.dripOperator().isDripInProgress(fundId), "I/DIP");
        _;
    }

    function setInvestPeriodUtils(address _investPeriodUtils) external onlyOwner {
        investPeriodUtils = InvestPeriod(_investPeriodUtils);
    }

    function newFund(uint256 fundId,
        bool hwm,
        uint256 investPeriod,
        address manager,
        IToken itoken,
        address tradeContract,
        uint256 indent
    ) external override {
        require(msg.sender == address(registry.fundFactory()), "I/AD"); // access denied
        require(!fundExist(fundId), "I/FE"); //fund exist
        registry.feeder().newFund(fundId, manager, itoken, tradeContract, hwm);

        funds[fundId] = FundInfo({
            trade: tradeContract,
            period: investPeriod,
            nextPeriod: 0,
            itoken: itoken,
            indent: indent,
            hwm: hwm
        });

        emit NewFund(fundId, manager, address(itoken));
    }

    // @notice Stake user's USDC and return shares amount
    function stake(uint256 fundId, uint256 amount) external override noDripInProgress(fundId) returns (uint256) {
        require(fundExist(fundId), "I/FNE");//fund NOT exist

        deposits[fundId] += amount;

        IERC20MetadataUpgradeable usdt = registry.usdt();
        IFeeder feeder = registry.feeder();
        usdt.approve(address(feeder), amount);
        require(usdt.transferFrom(msg.sender, address(feeder), amount), "I/TF");
        uint256 staked = feeder.stake(fundId, msg.sender, amount);

        emit Stake(fundId, msg.sender, staked, amount, amount - staked);

        return amount;
    }

    // @notice Put a request for withdrawing funds from the contract
    // Funds will be withdraw on the next vesting period
    // `amount` is amount of shares(i.e. ITKN)
    // If fund is closed, funds will be withdrawn immediately
    function unstake(uint256 fundId, uint256 amount) external override noDripInProgress(fundId) {
        require(fundExist(fundId), "I/FNE");
        require(amount > 0, "I/IA");
        require(funds[fundId].itoken.balanceOf(msg.sender) >= amount, "I/LE");
        uint256 nextUpgrade = registry.upgrader().nextUpgradeDate();
        require(nextUpgrade == 0 || nextUpgrade > block.timestamp, "I/UIP"); // upgrade in progress
        uint256 nextParamsUpdate = registry.tradeParamsUpdater().nearestUpdate(funds[fundId].trade);
        require(nextParamsUpdate == 0 || nextParamsUpdate > block.timestamp, "I/PUIP"); // params update in progress
        funds[fundId].itoken.burnFrom(msg.sender, amount);
        registry.feeder().requestWithdrawal(
            fundId,
            msg.sender, 
            amount,
            funds[fundId].indent > 0 &&
            nextPeriod(fundId) - funds[fundId].indent < block.timestamp &&
            (nextUpgrade == 0 || nextUpgrade > nextPeriod(fundId)) &&
            (nextParamsUpdate == 0 || nextParamsUpdate > nextPeriod(fundId)) &&
            getState(fundId) == FundState.Opened
        );

        emit UnStake(fundId, msg.sender, amount, funds[fundId].itoken.balanceOf(msg.sender));
    }

    function hide(uint256 fundId) external override {
        require(fundExist(fundId), "I/FNE");
        require(registry.feeder().managers(fundId) == msg.sender, "I/NAM");//not a manager
        require(getState(fundId) != FundState.Closed, "I/FNL"); // Fund not live

        ITrade(funds[fundId].trade).setState(FundState.Closed);

        emit FundStateChanged(fundId, getState(fundId));
    }

    function getState(uint256 fundId) public view returns(FundState) {
        return ITrade(funds[fundId].trade).status();
    }

    function show(uint256 fundId) external override {
        require(fundExist(fundId), "I/FNE");
        require(registry.feeder().managers(fundId) == msg.sender, "I/NAM");//not a manager
        require(getState(fundId) == FundState.Closed, "I/FL"); // Fund already live

        ITrade(funds[fundId].trade).setState(FundState.Opened);

        emit FundStateChanged(fundId, getState(fundId));
    }

    function cancelDeposit(uint256 fundId) external override noDripInProgress(fundId) {
        registry.feeder().cancelDeposit(fundId, msg.sender);
    }

    function cancelWithdraw(uint256 fundId) external override noDripInProgress(fundId) {
        uint256 tokens = registry.feeder().cancelWithdrawal(fundId, msg.sender);

        funds[fundId].itoken.mint(msg.sender, tokens);
    }

    function drip(uint256 fundId, uint256 tradeTvl) external override {
        require(msg.sender == address(registry.triggerServer()), "I/AD"); // access denied
        require(fundExist(fundId), "I/FNE");
        if (registry.dripOperator().drip(fundId, tradeTvl)) {
            emit NextPeriod(fundId, nextPeriod(fundId));
        }
    }

    function isDripEnabled(uint256 fundId) external override view returns(bool) {
        return registry.dripOperator().isDripEnabled(fundId);
    }

    function fundExist(uint256 fundId) public override view returns(bool) {
        return funds[fundId].trade != address(0);
    }

    function tokenForFund(uint256 fundId) public override view returns (address) {
        require(fundExist(fundId), "I/FNE");
        return address(funds[fundId].itoken);
    }

    function stakers(uint256 fundId) public override view returns (uint256) {
        IToken itoken = IToken(tokenForFund(fundId));
        return itoken.holders();
    }

    function estimatedWithdrawAmount(uint256 fundId, uint256 tradeTvl, uint256 amount) public override view returns (uint256) {
        IFeeder feeder = registry.feeder();
        uint256 pf = feeder.calculatePf(fundId, tradeTvl);
        return amount * feeder.tokenRate(fundId, tradeTvl - pf) / 10**18;
    }

    ///@return FundAddress, Investors amount, Next period ts
    function fundInfo(uint256 fundId) external override view returns (address, uint256, uint256) {
        return (
            funds[fundId].trade,
            stakers(fundId),
            nextPeriod(fundId)
        );
    }

    function tokenRate(uint256 fundId, uint256 tradeTvl) public override view returns (uint256) {
        return registry.feeder().tokenRate(fundId, tradeTvl);
    }

    function hwmValue(uint256 fundId) public override view returns (uint256) {
        return registry.feeder().hwmValue(fundId);
    }

    function userTVL(uint256 fundId, uint256 tradeTvl, address user) external override view returns (uint256) {
        return funds[fundId].itoken.balanceOf(user) * tokenRate(fundId, tradeTvl) / 10**18;
    }

    // @notice Get fund metrics for the current reporting period
    // @return Returns pending amounts to withdraw and deposit, as well as pending PF and USDT amount to close
    function pendingTvl(uint256[] calldata _funds, uint256[] calldata _tradeTvls, uint256 gasPrice) public override view returns(
        FundPendingTvlInfo[] memory results
    ) {
        IFeeder feeder = registry.feeder();
        results = new FundPendingTvlInfo[](_funds.length);
        for (uint256 i = 0; i < _funds.length; i++) {
            uint256 ef = feeder.getPendingExecutionFee(_funds[i], _tradeTvls[i], gasPrice);
            (uint256 toDeposit, uint256 toWithdraw, uint256 pf) = feeder.pendingTvl(
                _funds[i],
                _tradeTvls[i] > ef ? _tradeTvls[i] - ef : 0
            );
            int256 diff = int256(registry.usdt().balanceOf(funds[_funds[i]].trade))
                + int256(toDeposit)
                - int256(toWithdraw)
                - int256(pf)
                - int256(ef);
            results[i] = FundPendingTvlInfo(
                toDeposit,
                toWithdraw,
                pf,
                diff < 0 ? uint256(-diff) : 0,
                this.totalFees(_funds[i]),
                stakers(_funds[i]),
                feeder.fundTotalWithdrawals(_funds[i])
            );
        }
        return results;
    }

    function tokenSupply(uint256 fundId) public override view returns (uint256) {
        return funds[fundId].itoken.totalSupply();
    }

    function nextPeriod(uint256 fundId) public view returns (uint256) {
        return investPeriodUtils.getNextPeriodDate(funds[fundId].period, block.timestamp);
    }

    function userTokensAmount(uint256 fundId, address user) external override view returns (uint256) {
        return funds[fundId].itoken.balanceOf(user);
    }

    function totalFees(uint256 fundId) external view returns (uint256) {
        (uint256 live, uint256 sf, uint256 pf, uint256 mf) = registry.fees().gatheredFees(fundId);
        return sf + pf + mf;
    }

    function pendingDepositAndWithdrawals(uint256 fundId, address user) external view override returns (uint256, uint256, uint256){
        return registry.feeder().getUserAccrual(fundId, user);
    }
}

