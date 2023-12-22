// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.7.6;
pragma abicoder v2;

import "./EnumerableSet.sol";
import "./IMarket.sol";
import "./IPool.sol";
import "./IMarketLogic.sol";

contract Manager {
    using EnumerableSet for EnumerableSet.AddressSet;

    address public controller;      //controller, can change all config params
    address public router;          //router address
    address public vault;           //vault address
    address public riskFunding;     //riskFunding address
    address public inviteManager;   //inviteManager address

    uint256 public executeOrderFee = 0.0001 ether;  // execution fee of one order

    mapping(address => bool) signers;       // signers are qualified addresses to execute orders and update off-chain price
    mapping(address => bool) treasurers;    // vault administrators
    mapping(address => bool) liquidators;   // liquidators are qualified addresses to liquidate positions

    uint256 public communityExecuteOrderDelay;   // time elapse after that every one can execute orders
    uint256 public cancelElapse;            // time elapse after that user can cancel not executed orders
    uint256 public triggerOrderDuration;    // validity period of trigger orders

    bool public paused = true;              // protocol pause flag
    bool public isFundingPaused = true;     // funding mechanism pause flag
    bool public isInterestPaused = false;   // interests mechanism pause flag

    mapping(address => address) public getMakerByMarket;        // mapping of market to pool, market => pool
    mapping(address => address) public getMarketMarginAsset;    // mapping of market to base asset, market => base asset
    mapping(address => address) public getPoolBaseAsset;        // mapping of base asset and pool
    EnumerableSet.AddressSet internal markets;                  // enumerate of all markets
    EnumerableSet.AddressSet internal pools;                    // enumerate of all pools

    uint256 public orderNumLimit;                               //taker open order number limit

    event MarketCreated(address market, address pool, string indexToken, address marginAsset, uint8 marketType);
    event SignerAdded(address signer);
    event SignerRemoved(address signer);
    event Pause(bool paused);
    event Unpause(bool paused);
    event OrderNumLimitModified(uint256 _limit);
    event RouterModified(address _router);
    event ControllerModified(address _controller);
    event VaultModified(address _vault);
    event RiskFundingModified(address _riskFunding);
    event ExecuteOrderFeeModified(uint256 _feeToPriceProvider);
    event ExecuteOrderFeeOwnerModified(address _feeOwner);
    event InviteManagerModified(address _referralManager);
    event CancelElapseModified(uint256 _cancelElapse);
    event CommunityExecuteOrderDelayModified(uint256 _communityExecuteOrderDelay);
    event TriggerOrderDurationModified(uint256 triggerOrderDuration);
    event InterestStatusModified(bool _interestPaused);
    event FundingStatusModified(bool _fundingPaused);
    event TreasurerModified(address _treasurer, bool _isOpen);
    event LiquidatorModified(address _liquidator, bool _isOpen);

    modifier onlyController{
        require(msg.sender == controller, "Manager:only controller");
        _;
    }

    constructor(address _controller) {
        require(_controller != address(0), "Manager:address zero");
        controller = _controller;
    }

    /// @notice  pause the protocol
    function pause() external onlyController {
        require(!paused, "Manager:already paused");
        paused = true;
        emit Pause(paused);
    }

    /// @notice unpause the protocol
    function unpause() external onlyController {
        require(paused, "Manager:not paused");
        paused = false;
        emit Unpause(paused);
    }


    /// @notice modify liquidator
    /// @param _liquidator liquidator address
    /// @param _isOpen true open ;false close
    function modifyLiquidator(address _liquidator, bool _isOpen) external onlyController {
        require(_liquidator != address(0), "Manager:address error");
        liquidators[_liquidator] = _isOpen;
        emit LiquidatorModified(_liquidator, _isOpen);
    }

    /// @notice modify treasurer address
    /// @param _treasurer treasurer address
    /// @param _isOpen true open ;false close
    function modifyTreasurer(address _treasurer, bool _isOpen) external onlyController {
        require(_treasurer != address(0), "Manager:address error");
        treasurers[_treasurer] = _isOpen;
        emit TreasurerModified(_treasurer, _isOpen);
    }

    /// @notice modify order num limit of market
    /// @param _limit order num limit
    function modifyOrderNumLimit(uint256 _limit) external onlyController {
        require(_limit > 0, "Manager:limit error");
        orderNumLimit = _limit;
        emit OrderNumLimitModified(_limit);
    }

    /// @notice modify router address
    /// @param _router router address
    function modifyRouter(address _router) external onlyController {
        //        require(router == address(0), "router already notify");
        require(_router != address(0), "Manager:address zero");
        router = _router;
        emit RouterModified(_router);
    }

    /// @notice add a signer address
    /// @param _signer signer address
    function addSigner(address _signer) external onlyController {
        require(_signer != address(0), "Manager:address zero");
        signers[_signer] = true;
        emit SignerAdded(_signer);
    }

    /// @notice remove a signer address
    /// @param _signer signer address
    function removeSigner(address _signer) external onlyController {
        require(_signer != address(0), "Manager:address zero");
        signers[_signer] = false;
        emit SignerRemoved(_signer);
    }

    /// @notice modify controller address
    /// @param _controller controller address
    function modifyController(address _controller) external onlyController{
        require(_controller != address(0), "Manager:address zero");
        controller = _controller;
        emit ControllerModified(_controller);
    }

    /// @notice modify price provider fee owner address
    /// @param _riskFunding risk funding address
    function modifyRiskFunding(address _riskFunding) external onlyController {
        require(_riskFunding != address(0), "Manager:address zero");
        riskFunding = _riskFunding;
        emit RiskFundingModified(_riskFunding);
    }

    /// @notice activate or deactivate the interests module
    /// @param _interestPaused true:interest paused;false:interest not paused
    function modifyInterestStatus(bool _interestPaused) external onlyController {
        require(isInterestPaused != _interestPaused, "Manager:_interestPaused not change");

        for (uint256 i = 0; i < EnumerableSet.length(pools); i++) {
            IPool(EnumerableSet.at(pools, i)).updateBorrowIG();
        }

        isInterestPaused = _interestPaused;

        emit InterestStatusModified(_interestPaused);
    }

    /// @notice activate or deactivate
    /// @param _fundingPaused true:funding paused;false:funding not paused
    function modifyFundingStatus(bool _fundingPaused) external onlyController {
        require(isFundingPaused != _fundingPaused, "Manager:_fundingPaused not change");

        //update funding growth global
        for (uint256 i = 0; i < EnumerableSet.length(markets); i++) {
            IMarket(EnumerableSet.at(markets, i)).updateFundingGrowthGlobal();
        }

        isFundingPaused = _fundingPaused;

        emit FundingStatusModified(_fundingPaused);
    }

    /// @notice modify vault address
    /// @param _vault vault address
    function modifyVault(address _vault) external onlyController{
        require(_vault != address(0), "Manager:address zero");
        vault = _vault;
        emit VaultModified(_vault);
    }

    /// @notice modify price provider fee
    /// @param _fee price provider fee
    function modifyExecuteOrderFee(uint256 _fee) external onlyController{
        executeOrderFee = _fee;
        emit ExecuteOrderFeeModified(_fee);
    }

    /// @notice modify invite manager address
    /// @param _inviteManager invite manager address
    function modifyInviteManager(address _inviteManager) external onlyController{
        inviteManager = _inviteManager;
        emit InviteManagerModified(_inviteManager);
    }

    /// @notice modify cancel time elapse
    /// @param _cancelElapse cancel time elapse
    function modifyCancelElapse(uint256 _cancelElapse) external onlyController {
        require(_cancelElapse > 0, "Manager:_cancelElapse zero");
        cancelElapse = _cancelElapse;
        emit CancelElapseModified(_cancelElapse);
    }


    /// @notice modify community execute order delay time
    /// @param _communityExecuteOrderDelay execute time elapse
    function modifyCommunityExecuteOrderDelay(uint256 _communityExecuteOrderDelay) external onlyController {
        require(_communityExecuteOrderDelay > 0, "Manager:_communityExecuteOrderDelay zero");
        communityExecuteOrderDelay = _communityExecuteOrderDelay;
        emit CommunityExecuteOrderDelayModified(_communityExecuteOrderDelay);
    }

    /// @notice modify the trigger order validity period
    /// @param _triggerOrderDuration trigger order time dead line
    function modifyTriggerOrderDuration(uint256 _triggerOrderDuration) external onlyController {
        require(_triggerOrderDuration > 0, "Manager: time duration should > 0");
        triggerOrderDuration = _triggerOrderDuration;
        emit TriggerOrderDurationModified(_triggerOrderDuration);
    }

    /// @notice validate whether an address is a signer
    /// @param _signer signer address
    function checkSigner(address _signer) external view returns (bool) {
        return signers[_signer];
    }

    /// @notice validate whether an address is a treasurer
    /// @param _treasurer treasurer address
    function checkTreasurer(address _treasurer) external view returns (bool) {
        return treasurers[_treasurer];
    }

    /// @notice validate whether an address is a liquidator
    /// @param _liquidator liquidator address
    function checkLiquidator(address _liquidator) external view returns (bool) {
        return liquidators[_liquidator];
    }

    /// @notice validate whether an address is a controller
    function checkController(address _controller) view external returns (bool) {
        return _controller == controller;
    }

    /// @notice validate whether an address is the router
    function checkRouter(address _router) external view returns (bool) {
        return _router == router;
    }

    /// @notice validate whether an address is a legal market address
    function checkMarket(address _market) external view returns (bool) {
        return getMarketMarginAsset[_market] != address(0);
    }

    /// @notice validate whether an address is a legal pool address
    function checkPool(address _pool) external view returns (bool) {
        return getPoolBaseAsset[_pool] != address(0);
    }

    /// @notice create pair ,only controller can call
    /// @param pool pool address
    /// @param market market address
    /// @param token save price key
    /// @param marketType market type
    function createPair(
        address pool,
        address market,
        string memory token,
        uint8 marketType,
        MarketDataStructure.MarketConfig memory _config
    ) external onlyController {
        require(bytes(token).length != 0, 'Manager:indexToken is address(0)');
        require(marketType == 0 || marketType == 1 || marketType == 2, 'Manager:marketType error');
        require(pool != address(0) && market != address(0), 'Manager:market and maker is not address(0)');
        require(getMakerByMarket[market] == address(0), 'Manager:maker already exist');

        getMakerByMarket[market] = pool;
        address asset = IPool(pool).getBaseAsset();
        if(getPoolBaseAsset[pool] == address(0)){
            getPoolBaseAsset[pool] = asset;
        }
        require(getPoolBaseAsset[pool] == asset, 'Manager:pool base asset error');
        getMarketMarginAsset[market] = asset;
        
        EnumerableSet.add(markets, market);
        if (!EnumerableSet.contains(pools, pool)) {
            EnumerableSet.add(pools, pool);
        }
        IMarket(market).initialize(token, asset, pool, marketType);
        IPool(pool).registerMarket(market);
        
        _setMarketConfigInternal(market, _config);

        emit MarketCreated(market, pool, token, asset, marketType);
    }

    /// @notice set general market configurations, only controller can call
    /// @param _config configuration parameters
    function setMarketConfig(address market, MarketDataStructure.MarketConfig memory _config) public onlyController {
        _setMarketConfigInternal(market, _config);
    }

    function _setMarketConfigInternal(address market, MarketDataStructure.MarketConfig memory _config) internal {
        IMarketLogic(IMarket(market).marketLogic()).checkoutConfig(market, _config);
        IMarket(market).setMarketConfig(_config);
    }

    /// @notice modify the pause status for creating an order of a market
    /// @param market market address
    /// @param paused paused or not
    function modifyMarketCreateOrderPaused(address market, bool paused) public onlyController{
        MarketDataStructure.MarketConfig memory _config = IMarket(market).getMarketConfig();
        _config.createOrderPaused = paused;
        _setMarketConfigInternal(market, _config);
    }

    /// @notice modify the status for setting tpsl for an position
    /// @param market market address
    /// @param paused paused or not
    function modifyMarketTPSLPricePaused(address market, bool paused) public onlyController{
        MarketDataStructure.MarketConfig memory _config = IMarket(market).getMarketConfig();
        _config.setTPSLPricePaused = paused;
        _setMarketConfigInternal(market, _config);
    }

    /// @notice modify the pause status for creating a trigger order
    /// @param market market address
    /// @param paused paused or not
    function modifyMarketCreateTriggerOrderPaused(address market, bool paused) public onlyController {
        MarketDataStructure.MarketConfig memory _config = IMarket(market).getMarketConfig();
        _config.createTriggerOrderPaused = paused;
        _setMarketConfigInternal(market, _config);
    }

    /// @notice modify the pause status for updating the position margin
    /// @param market market address
    /// @param paused paused or not
    function modifyMarketUpdateMarginPaused(address market, bool paused) public onlyController {
        MarketDataStructure.MarketConfig memory _config = IMarket(market).getMarketConfig();
        _config.updateMarginPaused = paused;
        _setMarketConfigInternal(market, _config);
    }
    
    /// @notice get all markets
    function getAllMarkets() external view returns (address[] memory) {
        address[] memory _markets = new address[](EnumerableSet.length(markets));
        for (uint256 i = 0; i < EnumerableSet.length(markets); i++) {
            _markets[i] = EnumerableSet.at(markets, i);
        }
        return _markets;
    }

    /// @notice get all poolss
    function getAllPools() external view returns (address[] memory) {
        address[] memory _pools = new address[](EnumerableSet.length(pools));
        for (uint256 i = 0; i < EnumerableSet.length(pools); i++) {
            _pools[i] = EnumerableSet.at(pools, i);
        }
        return _pools;
    }
}

