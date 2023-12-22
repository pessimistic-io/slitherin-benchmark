// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./OwnableUpgradeable.sol";

import "./ERC1967Proxy.sol";
import "./BeaconProxy.sol";

import "./IInteraction.sol";
import "./IFundFactory.sol";
import "./IFees.sol";
import "./ITrade.sol";

import "./QHToken.sol";

contract FundFactory is Initializable, UUPSUpgradeable, OwnableUpgradeable, IFundFactory {

    address public usdt;
    address public feeder;
    IInteraction public interaction;
    IFees public fees;

    uint256 public newFundId; //not used. Remove on fresh deploy
    address public triggerServer;
    // AAVE data
    address public aaveLendingPool;
    address public aavePoolDataProvider;

    address public currentBeacon;

    address public gmxRouter;
    address public gmxPositionRouter;

    address public tradeAccess;

    function initialize(
        address usdt_,
        address feeder_,
        address fees_,
        address interaction_,
        address _poolDataProvider,
        address _lendingPool,
        address _tradingContract,
        address _triggerServer,
        address _tradeAccess
    ) public initializer {
        __Ownable_init();

        usdt = usdt_;
        feeder = feeder_;
        fees = IFees(fees_);
        interaction = IInteraction(interaction_);
        aavePoolDataProvider = _poolDataProvider;
        aaveLendingPool = _lendingPool;
        currentBeacon = _tradingContract;
        triggerServer = _triggerServer;
        tradeAccess = _tradeAccess;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function setAaveData(address _poolDataProvider, address _lendingPool) external onlyOwner {
        aavePoolDataProvider = _poolDataProvider;
        aaveLendingPool = _lendingPool;
    }

    function setUSDT(address usdt_) external onlyOwner {
        usdt = usdt_;
    }

    function setTradeAccess(address tradeAccess_) external onlyOwner {
        tradeAccess = tradeAccess_;
    }

    function setTradingContract(address trading_) external onlyOwner {
        currentBeacon = trading_;
    }

    function setFees(address fees_) external onlyOwner {
        require(fees_ != address(0), "FundFactory/invalid-fees");
        fees = IFees(fees_);

        emit FeesChanged(fees_);
    }

    function setInteraction(address interaction_) external onlyOwner {
        require(interaction_ != address(0), "FundFactory/invalid-interaction");
        interaction = IInteraction(interaction_);
    }

    function setFeeder(address feeder_) external onlyOwner {
        require(feeder_ != address(0), "FundFactory/invalid-feeder");
        feeder = feeder_;
    }

    function setTriggerServer(address trigger_) external onlyOwner {
        require(trigger_ != address(0), "FundFactory/invalid-trigger");
        triggerServer = trigger_;

        emit TriggerChanged(trigger_);
    }

    function setGMXData(address _gmxRouter, address _gmxPositionRouter) external onlyOwner {
        gmxRouter = _gmxRouter;
        gmxPositionRouter = _gmxPositionRouter;
    }

    function newFund(FundInfo calldata fundInfo) public override returns(uint256) {
        address manager = msg.sender;

        QHToken itoken = new QHToken(address(feeder), address(interaction), fundInfo.id);
        bytes memory emptyData;
        BeaconProxy trade = new BeaconProxy(currentBeacon, emptyData);
        ITrade(address(trade)).initialize(usdt,
            manager,
            triggerServer,
            feeder,
            address(interaction),
            aavePoolDataProvider,
            aaveLendingPool,
            tradeAccess
        );
        if (gmxRouter != address(0) && gmxPositionRouter != address(0)) {
            ITrade(address(trade)).setGMXData(gmxRouter, gmxPositionRouter);
        }

        interaction.newFund(fundInfo.id, fundInfo.hwm, fundInfo.investPeriod, 100, 100, manager, itoken, address(trade));
        fees.newFund(fundInfo.id, fundInfo.subscriptionFee, fundInfo.performanceFee, fundInfo.managementFee);

        emit FundCreated(manager, fundInfo.id, fundInfo.hwm,
            fundInfo.subscriptionFee, fundInfo.performanceFee, fundInfo.managementFee,
            fundInfo.investPeriod
        );

        return fundInfo.id;
    }
}

