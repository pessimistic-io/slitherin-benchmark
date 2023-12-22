// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC20.sol";

import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./IERC20MetadataUpgradeable.sol";

import "./Math.sol";
import "./IFeeder.sol";
import "./IFees.sol";
import "./ITrade.sol";
import "./IInteraction.sol";
import "./FundState.sol";

import "./WardedLivingUpgradeable.sol";

import "./console.sol";

interface WardedLike {
    function rely(address usr) external;
}

contract Interaction is Initializable, UUPSUpgradeable, OwnableUpgradeable, WardedLivingUpgradeable, IInteraction {

    uint256 public periodLength;

    IFeeder public feeder;
    address public factory; // TODO: remove unused
    address public triggerServer;
    IERC20 public usdt;

    mapping (uint256 => FundInfo) public funds;

    // Fund Id => amount
    mapping (uint256 => uint256) public deposits;
    mapping (uint256 => uint256) public withdrawals;

    IFees public fees;

    function initialize(
        address usdt_,
        address feeder_,
        address triggerServer_,
        address fees_
    ) public initializer {
        __Ownable_init();
        __WardedLiving_init();

        feeder = IFeeder(feeder_);
        triggerServer = triggerServer_;
        fees = IFees(fees_);

        usdt = IERC20(usdt_);
        usdt.approve(address(feeder), type(uint256).max);
    }

    function setInvestToken(address _newToken) external onlyOwner {
        usdt = IERC20(_newToken);
        usdt.approve(address(feeder), type(uint256).max);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function setFeeder(address feeder_) external auth {
        require(feeder_ != address(0), "I/IT");//invalid trigger
        feeder = IFeeder(feeder_);
        usdt.approve(address(feeder), type(uint256).max);
    }

    function setTrigger(address trigger_) external auth {
        require(trigger_ != address(0), "I/IT");//invalid trigger
        triggerServer = trigger_;
    }

    function newFund(uint256 fundId,
        bool hwm,
        uint256 investPeriod,
        uint256 minStakingAmount,
        uint256 minWithdrawalAmount,
        address manager,
        IToken itoken,
        address tradeContract
    ) external override auth live {
        require(!fundExist(fundId), "I/FE"); //fund exist

        feeder.newFund(fundId, manager, minStakingAmount, minWithdrawalAmount, itoken, tradeContract, hwm);

        funds[fundId] = FundInfo({
            trade: tradeContract,
            period: investPeriod,
            nextPeriod: block.timestamp + investPeriod,
            itoken: itoken,
            hwm: hwm
        });

        emit NewFund(fundId, manager, address(itoken));
    }

    // @notice Stake user's USDC and return shares amount
    function stake(uint256 fundId, uint256 amount) external override live returns (uint256) {
        require(fundExist(fundId), "I/FNE");//fund NOT exist

        deposits[fundId] += amount;

        require(usdt.transferFrom(msg.sender, address(feeder), amount), "Interaction::stake::transfer-failed");
        uint256 staked = feeder.stake(fundId, msg.sender, amount);

        emit Stake(fundId, msg.sender, staked, amount, amount - staked);

        return amount;
    }

    // @notice Put a request for withdrawing funds from the contract
    // Funds will be withdraw on the next vesting period
    // `amount` is amount of shares(i.e. ITKN)
    // If fund is closed, funds will be withdrawn immediately
    function unstake(uint256 fundId, uint256 amount) external override live {
        require(fundExist(fundId), "I/FNE");
        require(amount > 0, "I/IA");
        require(funds[fundId].itoken.balanceOf(msg.sender) >= amount, "I/LE");

        funds[fundId].itoken.burnFrom(msg.sender, amount);
        feeder.requestWithdrawal(fundId, msg.sender, amount);

        if (getState(fundId) == FundState.Closed) {
            // TODO: investigate case when autoclosing failed and we still have opened positions
            uint256 decimalsDiff = 18 - IERC20MetadataUpgradeable(address(usdt)).decimals() + 1;
            uint256 toWithdraw = amount / 10**decimalsDiff;
            ITrade(funds[fundId].trade).transferToFeeder(toWithdraw, address(feeder));
            address[] memory users = new address[](1);
            users[0] = msg.sender;
            uint256 supply = tokenSupply(fundId);
            uint256 tvl = (tokenSupply(fundId) + amount) / 10**decimalsDiff;
            uint256 pf = feeder.calculatePf(fundId, tvl);
            feeder.withdrawMultiple(fundId, users, supply, pf, tvl);
        }

        emit UnStake(fundId, msg.sender, amount, funds[fundId].itoken.balanceOf(msg.sender));
    }

    function hide(uint256 fundId) external override live {
        require(fundExist(fundId), "I/FNE");
        require(feeder.managers(fundId) == msg.sender, "I/NAM");//not a manager
        require(getState(fundId) != FundState.Closed, "I/FNL"); // Fund not live

        ITrade(funds[fundId].trade).setState(FundState.Closed);

        emit FundStateChanged(fundId, getState(fundId));
    }

    function getState(uint256 fundId) public view returns(FundState) {
        return ITrade(funds[fundId].trade).status();
    }

    function show(uint256 fundId) external override live {
        require(fundExist(fundId), "I/FNE");
        require(feeder.managers(fundId) == msg.sender, "I/NAM");//not a manager
        require(getState(fundId) == FundState.Closed, "I/FL"); // Fund already live

        ITrade(funds[fundId].trade).setState(FundState.Opened);

        emit FundStateChanged(fundId, getState(fundId));
    }

    function cancelDeposit(uint256 fundId) external override live {
        feeder.cancelDeposit(fundId, msg.sender);
    }

    function cancelWithdraw(uint256 fundId) external override live {
        uint256 tokens = feeder.cancelWithdrawal(fundId, msg.sender);

        funds[fundId].itoken.mint(msg.sender, tokens);
    }

    function drip(uint256 fundId, uint256 tradeTvl) public override live auth returns (uint256) {
        require(fundExist(fundId), "I/FNE");

        (uint256 toDeposit, uint256 toWithdraw, uint256 pf) = feeder.pendingTvl(fundId, tradeTvl);
        int256 tradeBalance = int256(ITrade(funds[fundId].trade).usdtAmount());
        int256 toFeeder = int256(toWithdraw) + int256(pf);
        int256 subtracted = toFeeder - tradeBalance;
        if (subtracted > 0) {
            // TODO: standardize errors?
            require(uint256(subtracted) < toDeposit, "Interaction/cant-subtract-from-stakes");
            toFeeder -= subtracted;
        } else {
            subtracted = 0;
        }

        if (toFeeder > 0) {
            ITrade(funds[fundId].trade).transferToFeeder(uint256(toFeeder), address(feeder));
        }

        feeder.gatherPF(fundId, tradeTvl);
        feeder.drip(fundId, funds[fundId].trade, uint256(subtracted), tradeTvl - pf);
        funds[fundId].nextPeriod = block.timestamp + funds[fundId].period;

        emit NextPeriod(fundId, funds[fundId].nextPeriod);
        return pf;
    }

    function dripAndWithdraw(uint256 fundId, uint256 tradeTvl, address[] calldata users) external override live auth {
        require(fundExist(fundId), "I/FNE");
        uint256 supply = tokenSupply(fundId);
        uint256 pf = drip(fundId, tradeTvl);
        feeder.withdrawMultiple(fundId, users, supply, pf, tradeTvl);
    }

    function burnFrom(uint256 fundId, address user, uint256 amount) external live auth {
        require(fundExist(fundId), "I/FNE");
        require(amount > 0, "I/IA");

        funds[fundId].itoken.burnFrom(user, amount);
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
        uint256 decimalsDiff = 36 - IERC20MetadataUpgradeable(address(usdt)).decimals();
        IToken itoken = IToken(tokenForFund(fundId));
        uint256 pf = feeder.calculatePf(fundId, tradeTvl);
        return amount * feeder.tokenRate(fundId, tradeTvl - pf) / 10**decimalsDiff;
    }

    ///@return FundAddress, Investors amount, Next period ts
    function fundInfo(uint256 fundId) external override view returns (address, uint256, uint256) {
        return (
            funds[fundId].trade,
            stakers(fundId),
            funds[fundId].nextPeriod
        );
    }

    function tokenRate(uint256 fundId, uint256 tradeTvl) public override view returns (uint256) {
        return feeder.tokenRate(fundId, tradeTvl);
    }

    function hwmValue(uint256 fundId) public override view returns (uint256) {
        return feeder.hwmValue(fundId);
    }

    function tokenSupply(uint256 fundId) public override view returns (uint256) {
        return funds[fundId].itoken.totalSupply();
    }

    function userTokensAmount(uint256 fundId, address user) external override view returns (uint256) {
        return funds[fundId].itoken.balanceOf(user);
    }

    function userTVL(uint256 fundId, uint256 tradeTvl, address user) external override view returns (uint256) {
        uint256 decimalsDiff = 36 - IERC20MetadataUpgradeable(address(usdt)).decimals();
        return funds[fundId].itoken.balanceOf(user) * tokenRate(fundId, tradeTvl) / 10**decimalsDiff;
    }

    // TODO: max _funds/_tradeTvls length? At least we need to paginate funds.
    // TODO: better naming
    // @notice Get fund metrics for the current reporting period
    // @return Returns pending amounts to withdraw and deposit, as well as pending PF and USDT amount to close
    function pendingTvl(uint256[] calldata _funds, uint256[] calldata _tradeTvls) public override view returns(
        FundPendingTvlInfo[] memory results
    ) {
        results = new FundPendingTvlInfo[](_funds.length);
        for (uint256 i = 0; i < _funds.length; i++) {
            (uint256 toDeposit, uint256 toWithdraw, uint256 pf) = feeder.pendingTvl(_funds[i], _tradeTvls[i]);
            uint256 balance = usdt.balanceOf(funds[_funds[i]].trade);
            uint256 mustBePaid = 0;
            int256 diff = int256(balance) + int256(toDeposit) - int256(toWithdraw) - int256(pf);
            if (diff < 0) {
                mustBePaid = uint256(-diff);
            }

            results[i] = FundPendingTvlInfo(
                toDeposit,
                toWithdraw,
                pf,
                mustBePaid,
                this.totalFees(_funds[i]),
                stakers(_funds[i])
            );
        }
        return results;
    }

    function setFees(address fees_) external onlyOwner {
        require(fees_ != address(0), "I/IF");
        fees = IFees(fees_);
    }

    function totalFees(uint256 fundId) external view returns (uint256) {
        (uint256 live, uint256 sf, uint256 pf, uint256 mf) = fees.gatheredFees(fundId);
        return sf + pf + mf;
    }

    function addTradeManager(uint256 fundId, address _newManager) external auth {
        ITrade(funds[fundId].trade).setManager(_newManager, true);
    }

    function pendingDepositAndWithdrawals(uint256 fundId, address user) external view override returns (uint256, uint256){
        return feeder.getUserAccrual(fundId, user);
    }

    function addTokenManager(uint256 fundId, address newManager_) external auth {
        WardedLike(address(funds[fundId].itoken)).rely(newManager_);
    }
}

