//SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.9 <=0.8.19;

import "./AccessControlEnumerableUpgradeable.sol";
import "./Initializable.sol";
import "./IERC20.sol";
import "./IFixedRateMarket.sol";
import "./IQollateralManager.sol";
import "./IFeeEmissionsQontroller.sol";
import "./ILiquidityEmissionsQontroller.sol";
import "./ITradingEmissionsQontroller.sol";
import "./IWETH.sol";
import "./IQAdmin.sol";
import "./IQodaLens.sol";
import "./CustomErrors.sol";
import "./QTypes.sol";

contract QAdmin is Initializable, AccessControlEnumerableUpgradeable, IQAdmin {
  
  /// @notice Identifier of the admin role
  bytes32 public constant ADMIN_ROLE = keccak256("ADMIN");

  /// @notice Identifier of the market role
  bytes32 public constant MARKET_ROLE = keccak256("MARKET");

  /// @notice Identifier of the role who allows accounts to mint tokens in QodaERC20
  bytes32 public constant MINTER_ROLE = keccak256("MINTER");

  /// @notice Identifier of the veToken role to do stake / unstake in StakingEmissionsQontroller
  bytes32 public constant VETOKEN_ROLE = keccak256("VETOKEN");
  
  /// @notice Reserve storage gap so introduction of new parent class later on can be done via upgrade
  uint256[50] __gap;

  /// @notice Contract for managing user collateral
  IQollateralManager private _qollateralManager;  

  /// @notice Contract for staking rewards
  address private _stakingEmissionsQontroller;

  /// @notice Contract for trading volume rewards
  ITradingEmissionsQontroller private _tradingEmissionsQontroller;

  /// @notice Contract for handling protocol fee charging and emission
  IFeeEmissionsQontroller private _feeEmissionsQontroller;

  /// @notice Contract for veQoda Token
  address private _veQoda;

  /// @notice Iterable list of all `Asset` addresses
  address[] private _allAssets;
  
  /// @notice Default value for `minCollateralRatio` if it is not defined in `_creditFacilityMap` for given address
  /// Scaled by 1e8
  uint private _minCollateralRatio;

  /// @notice Default value for `initCollateralRatio` if it is not defined in `_creditFacilityMap` for given address
  /// Scaled by 1e8
  uint private _initCollateralRatio;

  /// @notice The percent, ranging from 0% to 100%, of a liquidatable account's
  /// borrow that can be repaid in a single liquidate transaction.
  /// Scaled by 1e8
  uint private _closeFactor;

  /// @notice Grace period (in seconds) after maturity before liquidators are allowed to
  /// liquidate underwater accounts.
  uint private _repaymentGracePeriod;
  
  /// @notice Grace period (in seconds) after maturity before lenders are allowed to
  /// redeem their qTokens for underlying tokens
  uint private _maturityGracePeriod;
  
  /// @notice Additional collateral given to liquidator as incentive to liquidate
  /// underwater accounts. For example, if liquidation incentive is 1.1, liquidator
  /// receives extra 10% of borrowers' collateral
  /// Scaled by 1e8
  uint private _liquidationIncentive;
  
  /// @notice threshold in USD where protocol fee from each market will be transferred into `FeeEmissionsQontroller`
  /// once this amount is reached, scaled by 1e18
  uint private _thresholdUSD;

  /// @notice Mapping for the annualized fee for loans in basis points for each `FixedRateMarket`.
  /// The fee is charged to both the lender and the borrower on any given deal. The fee rate will
  /// need to be scaled for loans that mature outside of 1 year.
  /// Scaled by 1e4
  mapping(IFixedRateMarket => uint) private _protocolFee;

  /// @notice All enabled `Asset`s
  /// tokenAddress => Asset
  mapping(IERC20 => QTypes.Asset) private _assets;

  /// @notice Get the `FixedRateMarket` contract address for any given
  /// token and maturity time
  /// tokenAddress => maturity => fixedRateMarketAddress
  mapping(IERC20 => mapping(uint => address)) private _fixedRateMarkets;

  /// @notice Mapping for the MToken market corresponding to any underlying ERC20
  /// tokenAddress => mTokenAddress
  mapping(IERC20 => address) private _underlyingToMToken;
  
  /// @notice Mapping to determine whether a `FixedRateMarket` address
  /// is enabled or not
  /// fixedRateMarketAddress => bool
  mapping(address => bool) private _enabledMarkets;

  /// @notice Mapping to determine the minimum quote size for any `FixedRateMarket`
  /// in PV terms, denominated in local currency
  /// fixedRateMarketAddress => minQuoteSize
  mapping(address => uint) private _minQuoteSize;
  
  /// @notice Mapping to determine collateral ratio and credit limit of each address
  /// userAddress => creditInfo
  mapping(address => QTypes.CreditFacility) private _creditFacilityMap;
  
  /// @notice Contract for QodaLens
  IQodaLens private _qodaLens;
  
  /// @notice Contract for WETH
  IWETH private _weth;
  
  /// @notice Boolean to indicate if all markets are paused
  bool private _marketsPaused;
  
  /// @notice Mapping to indicate if specified contract address is paused
  mapping(address => bool) private _contractPausedMap;
  
  /// @notice Mapping to indicate if specified operation is paused
  mapping(uint => bool) private _operationPausedMap;
  
  /// @notice Contract for top-of-book quote rewards
  ILiquidityEmissionsQontroller private _liquidityEmissionsQontroller;
  
  constructor() {
    _disableInitializers();
  }
  
  /// @notice Constructor for upgradeable contracts
  function initialize(address admin) public initializer {

    // Initialize access control
    __AccessControlEnumerable_init();
    _grantRole(ADMIN_ROLE, admin);
    _grantRole(MARKET_ROLE, admin);
    _grantRole(MINTER_ROLE, admin);
    _grantRole(VETOKEN_ROLE, admin);
    _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);
    _setRoleAdmin(MARKET_ROLE, ADMIN_ROLE);
    _setRoleAdmin(MINTER_ROLE, ADMIN_ROLE);
    _setRoleAdmin(VETOKEN_ROLE, ADMIN_ROLE);
    
    // Set initial values for parameters
    _minCollateralRatio = 1e8;
    _initCollateralRatio = 1.1e8;
    _closeFactor = 0.5e8;
    _repaymentGracePeriod = 14400;
    _maturityGracePeriod = 28800;
    _liquidationIncentive = 1.1e8;
  }

  modifier onlyAdmin() {
    if (!hasRole(ADMIN_ROLE, msg.sender)) {
      revert CustomErrors.QA_OnlyAdmin();
    }
    _;
  }

  modifier onlyMarket() {
    if (!hasRole(MARKET_ROLE, msg.sender)) {
      revert CustomErrors.QA_OnlyMarket();
    }
    _;
  }

  modifier onlyVeToken() {
    if (!hasRole(VETOKEN_ROLE, msg.sender)) {
      revert CustomErrors.QA_OnlyVeToken();
    }
    _;
  }

  /** ADMIN FUNCTIONS **/
  
  /// @notice Call upon initialization after deploying `QAdmin` contract
  /// @param wethAddress Address of `WETH` contract of the network 
  function _setWETH(address wethAddress) external onlyAdmin {
    if (address(_weth) == address(0)) {
      // Initialize the value
      _weth = IWETH(wethAddress);
      
      // Emit the event
      emit SetWETH(wethAddress);
    }
  }

  /// @notice Call upon initialization after deploying `QollateralManager` contract
  /// @param qollateralManagerAddress Address of `QollateralManager` deployment
  function _setQollateralManager(address qollateralManagerAddress) external onlyAdmin {
    
    // Initialize the value
    _qollateralManager = IQollateralManager(qollateralManagerAddress);

    // Emit the event
    emit SetQollateralManager(qollateralManagerAddress);
  }

  /// @notice Call upon initialization after deploying `StakingEmissionsQontroller` contract
  /// @param stakingEmissionsQontrollerAddress Address of `StakingEmissionsQontroller` deployment
  function _setStakingEmissionsQontroller(address stakingEmissionsQontrollerAddress) external onlyAdmin {

    // Initialize the value
    _stakingEmissionsQontroller = stakingEmissionsQontrollerAddress;

    // Emit the event
    emit SetStakingEmissionsQontroller(stakingEmissionsQontrollerAddress);
  }

  /// @notice Call upon initialization after deploying `TradingEmissionsQontroller` contract
  /// @param tradingEmissionsQontrollerAddress Address of `TradingEmissionsQontroller` deployment
  function _setTradingEmissionsQontroller(address tradingEmissionsQontrollerAddress) external onlyAdmin {
    
    // Initialize the value
    _tradingEmissionsQontroller = ITradingEmissionsQontroller(tradingEmissionsQontrollerAddress);

    // Emit the event
    emit SetTradingEmissionsQontroller(tradingEmissionsQontrollerAddress);
  }

  /// @notice Call upon initialization after deploying `FeeEmissionsQontroller` contract
  /// @param feeEmissionsQontrollerAddress Address of `FeeEmissionsQontroller` deployment
  function _setFeeEmissionsQontroller(address feeEmissionsQontrollerAddress) external onlyAdmin {
    // Initialize the value
    _feeEmissionsQontroller = IFeeEmissionsQontroller(feeEmissionsQontrollerAddress);

    // Emit the event
    emit SetFeeEmissionsQontroller(feeEmissionsQontrollerAddress);
  }
  
  /// @notice Call upon initialization after deploying `LiquidityEmissionsQontroller` contract
  /// @param liquidityEmissionsQontrollerAddress Address of `LiquidityEmissionsQontroller` deployment
  function _setLiquidityEmissionsQontroller(address liquidityEmissionsQontrollerAddress) external onlyAdmin {
    // Initialize the value
    _liquidityEmissionsQontroller = ILiquidityEmissionsQontroller(liquidityEmissionsQontrollerAddress);

    // Emit the event
    emit SetLiquidityEmissionsQontroller(liquidityEmissionsQontrollerAddress);
  }

  /// @notice Call upon initialization after deploying `veQoda` contract
  /// @param veQodaAddress Address of `veQoda` deployment
  function _setVeQoda(address veQodaAddress) external onlyAdmin {

    // Initialize the value
    _veQoda = veQodaAddress;

    // Give `veQoda` the VETOKEN access control role
    _grantRole(VETOKEN_ROLE, veQodaAddress);

    // Emit the event
    emit SetVeQoda(veQodaAddress);
  }
  
  /// @notice Call upon initialization after deploying `QodaLens` contract
  /// @param qodaLensAddress Address of `QodaLens` deployment
  function _setQodaLens(address qodaLensAddress) external onlyAdmin {
    // Initialize the value
    _qodaLens = IQodaLens(qodaLensAddress);
    
    // Emit the event
    emit SetQodaLens(qodaLensAddress);
  }
  
  /// @notice Admin function for adding new Assets. An Asset must be added before it
  /// can be used as collateral or borrowed. Note: We can create functionality for
  /// allowing borrows of a token but not using it as collateral by setting
  /// `collateralFactor` to zero.
  /// @param tokenAddress ERC20 token corresponding to the Asset
  /// @param isYieldBearing True if token bears interest (eg aToken, cToken, mToken, etc)
  /// @param underlying Address of the underlying token
  /// @param oracleFeed_ Chainlink price feed address
  /// @param collateralFactor_ 0.0 to 1.0 (scaled to 1e8) for discounting risky assets
  /// @param marketFactor_ 0.0 to 1.0 (scaled to 1e8) for premium on risky borrows
  function _addAsset(
                     address tokenAddress,
                     bool isYieldBearing,
                     address underlying,
                     address oracleFeed_,
                     uint collateralFactor_,
                     uint marketFactor_
                     ) external onlyAdmin {
    
    IERC20 token = IERC20(tokenAddress);  

    // Cannot add the same asset twice
    if (_assets[token].isEnabled) {
      revert CustomErrors.QA_AssetExist();
    }

    // `collateralFactor` must be between 0 and 1 (scaled to 1e8)
    if (collateralFactor_ > MAX_COLLATERAL_FACTOR()) {
      revert CustomErrors.QA_InvalidCollateralFactor();
    }

    // `marketFactor` must be between 0 and 1 (scaled to 1e8)
    if (marketFactor_ > MAX_MARKET_FACTOR()) {
      revert CustomErrors.QA_InvalidMarketFactor();
    }

    // Initialize the `Asset` with the given parameters, and no enabled
    // maturities to begin with
    uint[] memory maturities_;
    QTypes.Asset memory asset = QTypes.Asset(
                                             true,
                                             isYieldBearing,
                                             underlying,
                                             oracleFeed_,
                                             collateralFactor_,
                                             marketFactor_,
                                             maturities_
                                             );
    _assets[token] = asset;
    _allAssets.push(tokenAddress);
    
    // Add yield-bearing assets to the (underlying => MToken) mapping
    if(isYieldBearing) {
      _underlyingToMToken[IERC20(underlying)]= tokenAddress;
    }
    
    // Emit the event
    emit AddAsset(tokenAddress, isYieldBearing, oracleFeed_, collateralFactor_, marketFactor_);
  }
  
  /// @notice Admin function for removing an asset
  /// @param token ERC20 token corresponding to the Asset
  function _removeAsset(IERC20 token) external onlyAdmin {
    QTypes.Asset memory asset = _assets[token];
    
    // Cannot delete non-existent asset
    if (!asset.isEnabled) {
      revert CustomErrors.QA_AssetNotExist();
    }
    
    // Remove from mapping if it is yield-bearing asset
    if(asset.isYieldBearing){
      delete _underlyingToMToken[IERC20(asset.underlying)];
    }
    
    // Remove from all assets by swapping with last element and pop it out
    uint allAssetsLength = _allAssets.length;
    for (uint i = 0; i < allAssetsLength;) {
      if (_allAssets[i] == address(token)) {
        _allAssets[i] = _allAssets[allAssetsLength - 1];
        _allAssets.pop();
        break;
      }
      unchecked { i++; }
    }
    
    // Remove token from asset
    delete _assets[token];
    
    // Emit the event
    emit RemoveAsset(address(token));
  }

  /// @notice Adds a new `FixedRateMarket` contract into the internal mapping of
  /// whitelisted market addresses
  /// @param marketAddress New `FixedRateMarket` contract address
  /// @param protocolFee_ Corresponding protocol fee in basis points
  /// @param minQuoteSize_ Size in PV terms, local currency
  function _addFixedRateMarket(
                               address marketAddress,
                               uint protocolFee_,
                               uint minQuoteSize_
                               ) external onlyAdmin {
    
    // Get the values from the corresponding `FixedRateMarket` contract
    IFixedRateMarket market = IFixedRateMarket(marketAddress);
    uint maturity = market.maturity();
    IERC20 token = market.underlyingToken();

    // Don't allow zero address
    if (address(token) == address(0)) {
      revert CustomErrors.QA_InvalidAddress();
    }

    // Only allow `Markets` where the corresponding `Asset` is enabled
    if (!_assets[token].isEnabled) {
      revert CustomErrors.QA_AssetNotSupported();
    }

    // Check that this market hasn't already been instantiated before
    if (_fixedRateMarkets[token][maturity] != address(0)) {
      revert CustomErrors.QA_MarketExist();
    }

    // Add the maturity as enabled to the corresponding Asset
    QTypes.Asset storage asset = _assets[token];
    asset.maturities.push(maturity);
    
    // Add newly-created `FixedRateMarket` to the lookup list
    _fixedRateMarkets[token][maturity] = marketAddress;

    // Enable newly-created `FixedRateMarket`
    _enabledMarkets[marketAddress] = true;

    // Give `FixedRateMarket` the MARKET access control role
    _grantRole(MARKET_ROLE, marketAddress);
    
    // Emit the event
    emit CreateFixedRateMarket(
                               marketAddress,
                               address(token),
                               maturity
                               );

    // Initialize the protocol fee for this `market`
    _setProtocolFee(marketAddress, protocolFee_);

    // Initialize the minimum `Quote` size for this `market`
    _setMinQuoteSize(marketAddress, minQuoteSize_);
  }
  
  function _removeFixedRateMarket(address marketAddress) external onlyAdmin {
    // Get the values from the corresponding `FixedRateMarket` contract
    IFixedRateMarket market = IFixedRateMarket(marketAddress);
    uint maturity = market.maturity();
    IERC20 token = market.underlyingToken();
    
    // Cannot delete non-existent market
    if (_fixedRateMarkets[token][maturity] == address(0)) {
      revert CustomErrors.QA_MarketNotExist();
    }

    // Remove from asset maturities by swapping with last element and pop it out
    QTypes.Asset storage asset = _assets[token];
    uint assetMaturitiesLength = asset.maturities.length;
    for(uint i = 0; i < assetMaturitiesLength;) {
      if (asset.maturities[i] == maturity) {
        asset.maturities[i] = asset.maturities[assetMaturitiesLength - 1];
        asset.maturities.pop();
        break;
      }
      unchecked { i++; }
    }
    
    // Remove market from existing market list
    delete _fixedRateMarkets[token][maturity];
    
    // Emit the event
    emit RemoveFixedRateMarket(
                               marketAddress,
                               address(token),
                               maturity
                               );
  }
  
  /// @notice Update the `collateralFactor` for a given `Asset`
  /// @param token ERC20 token corresponding to the Asset
  /// @param collateralFactor_ 0.0 to 1.0 (scaled to 1e8) for discounting risky assets
  function _setCollateralFactor(
                                IERC20 token,
                                uint collateralFactor_
                                ) external onlyAdmin {

    // Asset must already be enabled
    if (!_assets[token].isEnabled) {
      revert CustomErrors.QA_AssetNotEnabled();
    }

    // `collateralFactor` must be between 0 and 1 (scaled to 1e8)
    if (collateralFactor_ > MAX_COLLATERAL_FACTOR()) {
      revert CustomErrors.QA_InvalidCollateralFactor();
    }

    // Look up the corresponding asset
    QTypes.Asset storage asset = _assets[token];

    // Emit the event
    emit SetCollateralFactor(address(token), asset.collateralFactor, collateralFactor_);

    // Set `collateralFactor`
    asset.collateralFactor = collateralFactor_;
  }

  /// @notice Update the `marketFactor` for a given `Asset`
  /// @param token Address of the token corresponding to the Asset
  /// @param marketFactor_ 0.0 to 1.0 (scaled to 1e8) for discounting risky assets
  function _setMarketFactor(
                            IERC20 token,
                            uint marketFactor_
                            ) external onlyAdmin {

    // Asset must already be enabled
    if (!_assets[token].isEnabled) {
      revert CustomErrors.QA_AssetNotEnabled();
    }

    // `marketFactor` must be between 0 and 1 (scaled to 1e8)
    if (marketFactor_ > MAX_MARKET_FACTOR()) {
      revert CustomErrors.QA_InvalidMarketFactor();
    }

    // Look up the corresponding asset
    QTypes.Asset storage asset = _assets[token];

    // Emit the event
    emit SetMarketFactor(address(token), asset.marketFactor, marketFactor_);
    
    // Set `marketFactor`
    asset.marketFactor = marketFactor_;
  }

  /// @notice Set the minimum quote size for a particular `FixedRateMarket`
  /// @param marketAddress Address of the `FixedRateMarket` contract
  /// @param minQuoteSize_ Size in PV terms, local currency
  function _setMinQuoteSize(address marketAddress, uint minQuoteSize_) public onlyAdmin {
    IFixedRateMarket market = IFixedRateMarket(marketAddress);
    
    // `FixedRateMarket` must already exist
    if (_fixedRateMarkets[market.underlyingToken()][market.maturity()] == address(0)) {
      revert CustomErrors.QA_MarketNotExist();
    }

    // Emit the event
    emit SetMinQuoteSize(address(market), _minQuoteSize[marketAddress], minQuoteSize_);

    // Set `minQuoteSize`
    _minQuoteSize[marketAddress] = minQuoteSize_;
  }
  
  /// @notice Set the global minimum and initial collateral ratio
  /// @param minCollateralRatio_ New global minimum collateral ratio value
  /// @param initCollateralRatio_ New global initial collateral ratio value
  function _setCollateralRatio(uint minCollateralRatio_, uint initCollateralRatio_) external onlyAdmin {
    // `minCollateralRatio` should not be below 1
    if (minCollateralRatio_ < MANTISSA_COLLATERAL_RATIO()) {
      revert CustomErrors.QA_MinCollateralRatioNotLessThan1();
    }

    // `minCollateralRatio_` cannot be above `initCollateralRatio_`
    if (minCollateralRatio_ > initCollateralRatio_) {
      revert CustomErrors.QA_MinCollateralRatioNotGreaterThanInit();
    }

    // Emit the event
    emit SetCollateralRatio(_minCollateralRatio, _initCollateralRatio, minCollateralRatio_, initCollateralRatio_);
    
    // Set `_minCollateralRatio` to new value
    _minCollateralRatio = minCollateralRatio_;
    
    // Set `_initCollateralRatio` to new value
    _initCollateralRatio = initCollateralRatio_;
  }
  
  /// @notice Set credit facility for specified account
  /// @param account_ account for credit facility adjustment
  /// @param enabled_ If credit facility should be enabled 
  /// @param minCollateralRatio_ New minimum collateral ratio value
  /// @param initCollateralRatio_ New initial collateral ratio value
  /// @param creditLimit_ new credit limit in USD, scaled by 1e18
  function _setCreditFacility(address account_, bool enabled_, uint minCollateralRatio_, uint initCollateralRatio_, uint creditLimit_) external onlyAdmin {
    // `minCollateralRatio_` cannot be above `initCollateralRatio_` 
    if (minCollateralRatio_ > initCollateralRatio_) {
      revert CustomErrors.QA_MinCollateralRatioNotGreaterThanInit();
    }
    // Emit the event
    emit SetCreditFacility(
      account_, 
      _creditFacilityMap[account_].enabled,
      _creditFacilityMap[account_].minCollateralRatio, 
      _creditFacilityMap[account_].initCollateralRatio,
      _creditFacilityMap[account_].creditLimit,
      enabled_,
      minCollateralRatio_, 
      initCollateralRatio_,
      creditLimit_);
    
    // Set CreditFacility to new value
    _creditFacilityMap[account_].enabled = enabled_;
    _creditFacilityMap[account_].minCollateralRatio = minCollateralRatio_;
    _creditFacilityMap[account_].initCollateralRatio = initCollateralRatio_;
    _creditFacilityMap[account_].creditLimit = creditLimit_;
  }
  
  /// @notice Set the global close factor
  /// @param closeFactor_ New close factor value
  function _setCloseFactor(uint closeFactor_) external onlyAdmin {
    
    // `_closeFactor` needs to be between 0 and 1
    if (closeFactor_ > MANTISSA_FACTORS()) {
      revert CustomErrors.QA_OverThreshold(closeFactor_, MANTISSA_FACTORS());
    }

    // Emit the event
    emit SetCloseFactor(_closeFactor, closeFactor_);
    
    // Set `_closeFactor` to new value
    _closeFactor = closeFactor_;
  }

  /// @notice Set the global repayment grace period
  /// @param repaymentGracePeriod_ New repayment grace period
  function _setRepaymentGracePeriod(uint repaymentGracePeriod_) external onlyAdmin {

    // `_repaymentGracePeriod` needs to be <= 60*60*24 (ie 24 hours)
    if (repaymentGracePeriod_ > 86400) {
      revert CustomErrors.QA_OverThreshold(repaymentGracePeriod_, 86400);
    }

    // Emit the event
    emit SetRepaymentGracePeriod(_repaymentGracePeriod, repaymentGracePeriod_);

    // set `_repaymentGracePeriod` to new value
    _repaymentGracePeriod = repaymentGracePeriod_;
  }

  /// @notice Set the global maturity grace period
  /// @param maturityGracePeriod_ New maturity grace period
  function _setMaturityGracePeriod(uint maturityGracePeriod_) external onlyAdmin {
    
    // `_maturityGracePeriod` needs to be <= 60*60*24 (ie 24 hours)
    if (maturityGracePeriod_ > 86400) {
      revert CustomErrors.QA_OverThreshold(maturityGracePeriod_, 86400);
    }

    // Emit the event
    emit SetMaturityGracePeriod(_maturityGracePeriod, maturityGracePeriod_);
    
    // set `_maturityGracePeriod` to new value
    _maturityGracePeriod = maturityGracePeriod_;
  }
  
  /// @notice Set the global liquidation incetive
  /// @param liquidationIncentive_ New liquidation incentive value
  function _setLiquidationIncentive(uint liquidationIncentive_) external onlyAdmin {

    // `_liquidationIncentive` needs to be greater than or equal to 1
    if (liquidationIncentive_ < MANTISSA_FACTORS()) {
      revert CustomErrors.QA_UnderThreshold(liquidationIncentive_, MANTISSA_FACTORS());
    }

    // Emit the event
    emit SetLiquidationIncentive(_liquidationIncentive, liquidationIncentive_);   
    
    // Set `_liquidationIncentive` to new value
    _liquidationIncentive = liquidationIncentive_;
  }

  /// @notice Set the annualized protocol fees for each market in basis points
  /// @param marketAddress Address of the `FixedRateMarket` contract
  /// @param protocolFee_ New protocol fee value (scaled to 1e4)
  function _setProtocolFee(address marketAddress, uint protocolFee_) public onlyAdmin {

    // Max annual protocol fees of 250 basis points
    if (protocolFee_ > 250) {
      revert CustomErrors.QA_OverThreshold(protocolFee_, 250);
    }

    // Min annual protocol fees of 1 basis point
    if (protocolFee_ < 1) {
      revert CustomErrors.QA_UnderThreshold(protocolFee_, 1);
    }
    
    // Make sure market address must exist and is enabled
    if (!_enabledMarkets[marketAddress]) {
      revert CustomErrors.QA_InvalidAddress();
    }
    
    // Casting from address into corresponding interface 
    IFixedRateMarket market = IFixedRateMarket(marketAddress);
    
    // Emit the event
    emit SetProtocolFee(_protocolFee[market], protocolFee_);
    
    // Set `_protocolFee` to new value
    _protocolFee[market] = protocolFee_;
  }

  /// @notice Set the global threshold in USD for protocol fee transfer
  /// @param thresholdUSD_ New threshold USD value (scaled by 1e18)
  function _setThresholdUSD(uint thresholdUSD_) external onlyAdmin {
    _thresholdUSD = thresholdUSD_;
  }
  
  /// @notice Pause/unpause all markets for admin
  /// @param paused Boolean to indicate if all markets should be paused
  function _setMarketsPaused(bool paused) external onlyAdmin {
    if (_marketsPaused != paused) {
      // Set `_marketsPaused` to new value
      _marketsPaused = paused;
      
      // Emit the event
      emit SetMarketPaused(paused);
    }
  }
  
  /// @notice Pause/unpause specified list of contracts for admin
  /// @param contractsAddr List of contract addresses to pause/unpause
  /// @param paused Boolean to indicate if specified contract should be paused
  function _setContractPaused(address[] memory contractsAddr, bool paused) external onlyAdmin {
    uint contractAddrLength = contractsAddr.length;
    for (uint i = 0; i < contractAddrLength;) {
      _setContractPaused(contractsAddr[i], paused);
      unchecked { i++; }
    }
  }
  
  /// @notice Pause/unpause specified contract for admin
  /// @param contractAddr Address of contract to pause/unpause
  /// @param paused Boolean to indicate if specified contract should be paused
  function _setContractPaused(address contractAddr, bool paused) public onlyAdmin {
    if (_contractPausedMap[contractAddr] != paused) {
      // Set address in `_contractPausedMap` to new value
      _contractPausedMap[contractAddr] = paused;
      
      // Emit the event
      emit SetContractPaused(contractAddr, paused);
    }
  }
  
  /// @notice Pause/unpause specified list of operations for admin
  /// @param operationIds List of ids for operation to pause/unpause
  /// @param paused Boolean to indicate if specified operation should be paused
  function _setOperationPaused(uint[] memory operationIds, bool paused) external onlyAdmin {
    uint operationIdsLength = operationIds.length;
    for (uint i = 0; i < operationIdsLength;) {
      _setOperationPaused(operationIds[i], paused);
      unchecked { i++; }
    }
  }
  
  /// @notice Pause/unpause specified operation for admin
  /// @param operationId Id for operation to pause/unpause
  /// @param paused Boolean to indicate if specified operation should be paused
  function _setOperationPaused(uint operationId, bool paused) public onlyAdmin {
    if (_operationPausedMap[operationId] != paused) {
      // Set id in `_operationPausedMap` to new value
      _operationPausedMap[operationId] = paused;
      
      // Emit the event
      emit SetOperationPaused(operationId, paused);
    }
  }

  /** VIEW FUNCTIONS **/
  
  /// @notice Get the address of the `WETH` contract
  function WETH() external view returns(address) {
    return address(_weth);
  }
  
  /// @notice Get the address of the `QollateralManager` contract
  function qollateralManager() external view returns(address) {
    return address(_qollateralManager);
  }

  /// @notice Get the address of the `QPriceOracle` contract
  function qPriceOracle() external view returns(address) {
    if(address(_qollateralManager) != address(0)){
      return _qollateralManager.qPriceOracle();
    }else {
      return address(0);
    }
  }

  /// @notice Get the address of the `StakingEmissionsQontroller` contract
  function stakingEmissionsQontroller() external view returns(address) {
    return _stakingEmissionsQontroller;
  }

  /// @notice Get the address of the `TradingEmissionsQontroller` contract
  function tradingEmissionsQontroller() external view returns(address) {
    return address(_tradingEmissionsQontroller);
  }

  /// @notice Get the address of the `FeeEmissionsQontroller` contract
  function feeEmissionsQontroller() external view returns(address) {
    return address(_feeEmissionsQontroller);
  }
  
  /// @notice Get the address of the `LiquidityEmissionsQontroller` contract
  function liquidityEmissionsQontroller() external view returns(address) {
    return address(_liquidityEmissionsQontroller);
  }

  /// @notice Get the address of the `veQoda` contract
  function veQoda() external view returns(address) {
    return _veQoda;
  }
  
  /// @notice Get the address of the `QodaLens` contract
  function qodaLens() external view returns(address) {
    return address(_qodaLens);
  }

  /// @notice Get the credit limit with associated address, scaled by 1e6
  function creditLimit(address account_) external view returns(uint) {
    return _creditFacilityMap[account_].enabled? _creditFacilityMap[account_].creditLimit: UINT_MAX();
  }
  
  /// @notice Gets the `Asset` mapped to the address of a ERC20 token
  /// @param token ERC20 token
  /// @return QTypes.Asset Associated `Asset`
  function assets(IERC20 token) external view returns(QTypes.Asset memory) {
    return _assets[token];
  }

  /// @notice Get all enabled `Asset`s
  /// @return address[] iterable list of enabled `Asset`s
  function allAssets() external view returns(address[] memory) {
    return _allAssets;
  }

  /// @notice Gets the `oracleFeed` associated with a ERC20 token
  /// @param token ERC20 token
  /// @return address Address of the oracle feed
  function oracleFeed(IERC20 token) external view returns(address) {
    return _assets[token].oracleFeed;
  }
  
  /// @notice Gets the `CollateralFactor` associated with a ERC20 token
  /// @param token ERC20 token
  /// @return uint Collateral Factor, scaled by 1e8
  function collateralFactor(IERC20 token) external view returns(uint) {
    return _assets[token].collateralFactor;
  }

  /// @notice Gets the `MarketFactor` associated with a ERC20 token
  /// @param token ERC20 token
  /// @return uint Market Factor, scaled by 1e8
  function marketFactor(IERC20 token) external view returns(uint) {
    return _assets[token].marketFactor;
  }

  /// @notice Gets the `maturities` associated with a ERC20 token
  /// @param token ERC20 token
  /// @return uint[] array of UNIX timestamps (in seconds) of the maturity dates
  function maturities(IERC20 token) external view returns(uint[] memory) {
    return _assets[token].maturities;
  }
  
  /// @notice Get the MToken market corresponding to any underlying ERC20
  /// tokenAddress => mTokenAddress
  function underlyingToMToken(IERC20 token) external view returns(address) {
    return _underlyingToMToken[token];
  }
  
  /// @notice Gets the address of the `FixedRateMarket` contract
  /// @param token ERC20 token
  /// @param maturity UNIX timestamp of the maturity date
  /// @return address Address of `FixedRateMarket` contract
  function fixedRateMarkets(
                            IERC20 token,
                            uint maturity
                            ) external view returns(address){
    return _fixedRateMarkets[token][maturity];
  }

  /// @notice Check whether an address is a valid FixedRateMarket address.
  /// Can be used for checks for inter-contract admin/restricted function call.
  /// @param marketAddress Address of the `FixedRateMarket` contract
  /// @return bool True if valid false otherwise
  function isMarketEnabled(address marketAddress) external view returns(bool){
    return _enabledMarkets[marketAddress];
  }  

  function minQuoteSize(address marketAddress) external view returns(uint) {
    return _minQuoteSize[marketAddress];
  }
  
  function minCollateralRatio() public view returns(uint){
    return minCollateralRatio(msg.sender);
  }
  
  function minCollateralRatio(address account) public view returns(uint){
    return _creditFacilityMap[account].enabled? _creditFacilityMap[account].minCollateralRatio: _minCollateralRatio;
  }

  function initCollateralRatio() public view returns(uint){
    return initCollateralRatio(msg.sender);
  }
  
  function initCollateralRatio(address account) public view returns(uint){
    return _creditFacilityMap[account].enabled? _creditFacilityMap[account].initCollateralRatio: _initCollateralRatio;
  }

  function closeFactor() public view returns(uint){
    return _closeFactor;
  }

  function repaymentGracePeriod() public view returns(uint){
    return _repaymentGracePeriod;
  }

  function maturityGracePeriod() public view returns(uint){
    return _maturityGracePeriod;
  }
  
  function liquidationIncentive() public view returns(uint){
    return _liquidationIncentive;
  }

  /// @notice Annualized protocol fee in basis points, scaled by 1e4
  function protocolFee(address marketAddress) public view returns(uint) {
    return _protocolFee[IFixedRateMarket(marketAddress)];
  }

  /// @notice threshold in USD where protocol fee from each market will be transferred into `FeeEmissionsQontroller`
  /// once this amount is reached, scaled by 1e6
  function thresholdUSD() external view returns(uint) {
    return _thresholdUSD;
  }
  
  /// @notice Boolean to indicate if all markets are paused
  function marketsPaused() external view returns(bool) {
    return _marketsPaused;
  }
  
  /// @notice Boolean to indicate if specified contract address is paused
  function contractPaused(address contractAddr) external view returns(bool) {
    return _contractPausedMap[contractAddr];
  }
  
  /// @notice Boolean to indicate if specified operation is paused
  function operationPaused(uint operationId) external view returns(bool) {
    return _operationPausedMap[operationId];
  }
  
  /// @notice Check if given combination of contract address and operation should be allowed
  function isPaused(address contractAddr, uint operationId) external view returns(bool) {
    // Check if address is a market and if market is paused
    if (_marketsPaused && _enabledMarkets[contractAddr]) {
      return true;
    }
    // Check if pausing is applied for a particular contract 
    if (_contractPausedMap[contractAddr]) {
      return true;
    }
    // Check if pausing is applied for a particular operation
    if (_operationPausedMap[operationId]) {
      return true;
    }
    return false;
  }
  
  /// @notice 2**256 - 1
  function UINT_MAX() public pure returns(uint){
    return type(uint).max;
  }
  
  /// @notice Generic mantissa corresponding to ETH decimals
  function MANTISSA_DEFAULT() public pure returns(uint){
    return 1e18;
  }

  /// @notice Mantissa for USD
  function MANTISSA_USD() public pure returns(uint){
    return 1e18;
  }
  
  /// @notice Mantissa for collateral ratio
  function MANTISSA_COLLATERAL_RATIO() public pure returns(uint){
    return 1e8;
  }

  /// @notice `assetFactor` and `marketFactor` have up to 8 decimal places precision
  function MANTISSA_FACTORS() public pure returns(uint){
    return 1e8;
  }

  /// @notice Basis points have 4 decimal place precision
  function MANTISSA_BPS() public pure returns(uint){
    return 1e4;
  }

  /// @notice Staked Qoda has 6 decimal place precision
  function MANTISSA_STAKING() public pure returns(uint) {
    return 1e6;
  }
  
  /// @notice `collateralFactor` cannot be above 1.0
  function MAX_COLLATERAL_FACTOR() public pure returns(uint){
    return 1e8;
  }

  /// @notice `marketFactor` cannot be above 1.0
  function MAX_MARKET_FACTOR() public pure returns(uint){
    return 1e8;
  }
  
  /// @notice version number of this contract, will be bumped upon contractual change
  function VERSION_NUMBER() public pure returns(string memory){
    return "0.2.10";
  }
  
}

