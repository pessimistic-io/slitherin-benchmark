//SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.9 <=0.8.19;

import "./Initializable.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./IFixedRateMarket.sol";
import "./IQAdmin.sol";
import "./IQPriceOracle.sol";
import "./IQollateralManager.sol";
import "./IQToken.sol";
import "./IWETH.sol";
import "./MTokenInterfaces.sol";
import "./CustomErrors.sol";
import "./QTypes.sol";
import "./Utils.sol";

contract QollateralManager is Initializable, IQollateralManager {

  using SafeERC20 for IERC20;
    
  /// @notice Reserve storage gap so introduction of new parent class later on can be done via upgrade
  uint256[50] __gap;
  
  /// @notice Contract storing all global Qoda parameters
  IQAdmin private _qAdmin;

  /// @notice Contract for price oracle feeds
  IQPriceOracle private _qPriceOracle;

  /// @notice 0x0 null address for convenience
  address constant NULL = address(0);
  
  /// @notice Use this for quick lookups of collateral balances by asset
  /// account => tokenAddress => balanceLocal
  mapping(address => mapping(IERC20 => uint)) private _collateralBalances;

  /// @notice Iterable list of all collateral addresses which an account has nonzero balance.
  /// Use this when calculating `collateralValue` for liquidity considerations
  /// account => tokenAddresses[]
  mapping(address => IERC20[]) private _iterableCollateralAddresses;
  
  /// @notice Iterable list of all markets which an account has participated.
  /// Use this when calculating `totalBorrowValue` for liquidity considerations
  /// account => fixedRateMarketAddresses[]
  mapping(address => IFixedRateMarket[]) private _iterableAccountMarkets;

  /// @notice Non-iterable list of collateral which an account has nonzero balance.
  /// Use this for quick lookups
  /// account => tokenAddress => bool;
  mapping(address => mapping(IERC20 => bool)) private _accountCollateral;

  /// @notice Non-iterable list of markets which an account has participated.
  /// Use this for quick lookups
  /// account => fixedRateMarketAddress => bool;
  mapping(address => mapping(IFixedRateMarket => bool)) private _accountMarkets;
  
  uint256 private constant _NOT_ENTERED = 1;
  uint256 private constant _ENTERED = 2;

  /// @notice Same as _status in `@openzeppelin/contracts/security/ReentrancyGuard.sol`
  /// Reconstruct here instead of inheritance is to avoid storage slot sequence problem during
  /// contract upgrade
  uint256 private _status;
  
  constructor() {
    _disableInitializers();
  }
  
  /// @notice Constructor for upgradeable contracts
  /// @param qAdminAddress_ Address of the `QAdmin` contract
  /// @param qPriceOracleAddress_ Address of the `QPriceOracle` contract
  function initialize(address qAdminAddress_, address qPriceOracleAddress_) external initializer {
    _qAdmin = IQAdmin(qAdminAddress_);
    _qPriceOracle = IQPriceOracle(qPriceOracleAddress_);
    _status = _NOT_ENTERED;
  }

  /// @notice Needed for receiving native token when redeeming from Moonwell
  receive() external payable {
    // If it is not from WETH and not from yield-bearing asset, refund it back to sender
    QTypes.Asset memory senderAsset = _qAdmin.assets(IERC20(msg.sender));
    bool isSenderYieldBearingAsset = senderAsset.isEnabled && senderAsset.isYieldBearing;
    if (msg.sender != _qAdmin.WETH() && !isSenderYieldBearingAsset) {
      Utils.refundExcessiveETH(0);
    }
  }

  modifier onlyAdmin() {
    if (!_qAdmin.hasRole(_qAdmin.ADMIN_ROLE(), msg.sender)) {
      revert CustomErrors.QM_OnlyAdmin();
    }
    _;
  }

  modifier onlyMarket() {
    if (!_qAdmin.hasRole(_qAdmin.MARKET_ROLE(), msg.sender)) {
      revert CustomErrors.QM_OnlyMarket();
    }
    _;
  }
  
  /// @notice Modifier which checks that contract and specified operation is not paused
  modifier whenNotPaused(uint operationId) {
    if (_qAdmin.isPaused(address(this), operationId)) {
      revert CustomErrors.QM_OperationPaused(operationId);
    }
    _;
  }
  
  /// @notice Logic copied from `@openzeppelin/contracts/security/ReentrancyGuard.sol`
  /// Reconstruct here instead of inheritance is to avoid storage slot sequence problem during
  /// contract upgrade
  modifier nonReentrant() {
    // On the first call to nonReentrant, _notEntered will be true
    if (_status == _ENTERED) {
      revert CustomErrors.QM_ReentrancyDetected();
    }

    // Any calls to nonReentrant after this point will fail
    _status = _ENTERED;

    _;

    // By storing the original value once again, a refund is triggered (see
    // https://eips.ethereum.org/EIPS/eip-2200)
    _status = _NOT_ENTERED;
  }
  
  /** ADMIN/RESTRICTED FUNCTIONS **/

  /// @notice Record when an account has either borrowed or lent into a
  /// `FixedRateMarket`. This is necessary because we need to iterate
  /// across all markets that an account has borrowed/lent to to calculate their
  /// `borrowValue`. Only the `FixedRateMarket` contract itself may call
  /// this function
  /// @param account User account
  /// @param market Address of the `FixedRateMarket` market
  function _addAccountMarket(address account, IFixedRateMarket market) external onlyMarket {

    // Record that account now has participated in this `FixedRateMarket`
    if(!_accountMarkets[account][market]){
      _accountMarkets[account][market] = true;
      _iterableAccountMarkets[account].push(market);
    }

    /// Emit the event
    emit AddAccountMarket(account, address(market));
  }

  /// @notice Transfer collateral balances from one account to another. Only
  /// `FixedRateMarket` contracts can call this restricted function. This is used
  /// for when a liquidator liquidates an account.
  /// @param token ERC20 token
  /// @param from Sender address
  /// @param to Recipient address
  /// @param amount Amount to transfer
  function _transferCollateral(
                               IERC20 token,
                               address from,
                               address to,
                               uint amount
                               ) external onlyMarket {
    // Amount must be positive
    if (amount <= 0) {
      revert CustomErrors.QM_ZeroTransferAmount();
    }

    // Check `from` address has enough collateral balance
    if (amount > _collateralBalances[from][token]) {
      revert CustomErrors.QM_InsufficientCollateralBalance();
    }

    // Transfer the balance to recipient    
    _subtractCollateral(from, token, amount);
    token.safeTransfer(to, amount);

    // Emit the event
    emit TransferCollateral(address(token), from, to, amount);    
  }

  /** USER INTERFACE **/

  /// @notice Users call this to deposit collateral to fund their borrows
  /// @param token ERC20 token
  /// @param amount Amount to deposit (in local ccy)
  /// @return uint New collateral balance
  function depositCollateral(IERC20 token, uint amount) external whenNotPaused(101) returns(uint) {
    return _depositCollateral(msg.sender, token, amount);
  }

  /// @notice Users call this to deposit collateral to fund their borrows, where their
  /// collateral is automatically wrapped into MTokens for convenience so users can
  /// automatically earn interest on their collateral.
  /// @param underlying Underlying ERC20 token
  /// @param amount Amount to deposit (in underlying local currency)
  /// @return uint New collateral balance (in MToken balance)
  function depositCollateralWithMTokenWrap(IERC20 underlying, uint amount) external whenNotPaused(101) returns(uint) {
    return _depositCollateralWithMTokenWrap(msg.sender, underlying, amount, false);
  }
  
  /// @notice Users call this to deposit collateral to fund their borrows, where their
  /// collateral is automatically wrapped from ETH to WETH.
  /// @return uint New collateral balance (in WETH balance)
  function depositCollateralWithETH() external payable whenNotPaused(101) returns(uint) {
    return _depositCollateralWithETH(msg.sender, msg.value);
  } 

  /// @notice Users call this to deposit collateral to fund their borrows, where their
  /// collateral is automatically wrapped from ETH into MTokens for convenience so users can
  /// automatically earn interest on their collateral.
  /// @return uint New collateral balance (in MToken balance)
  function depositCollateralWithMTokenWrapWithETH() external payable whenNotPaused(101) returns(uint) {
    return _depositCollateralWithMTokenWrap(msg.sender, IERC20(_qAdmin.WETH()), msg.value, true);
  }
    
  /// @notice Users call this to withdraw collateral
  /// @param token ERC20 token
  /// @param amount Amount to withdraw (in local ccy)
  /// @return uint New collateral balance 
  function withdrawCollateral(IERC20 token, uint amount) external nonReentrant whenNotPaused(102) returns(uint) {
    return _withdrawCollateral(msg.sender, token, amount);
  }

  /// @notice Users call this to withdraw mToken collateral, where their
  /// collateral is automatically unwrapped into underlying tokens for
  /// convenience.
  /// @param mTokenAddress Yield-bearing token address
  /// @param amount Amount to withdraw (in mToken local currency)
  /// @return uint New collateral balance (in MToken balance)
  function withdrawCollateralWithMTokenUnwrap(
                                              address mTokenAddress,
                                              uint amount
                                              ) external nonReentrant whenNotPaused(102) returns(uint) {
    return _withdrawCollateralWithMTokenUnwrap(msg.sender, mTokenAddress, amount, false);
  }
  
  /// @notice Users call this to withdraw ETH collateral, where their
  /// collateral is automatically unwrapped from WETH for convenience.
  /// @param amount Amount to withdraw (in WETH local currency)
  /// @return uint New collateral balance (in WETH balance)
  function withdrawCollateralWithETH(uint amount) external nonReentrant whenNotPaused(102) returns(uint) {
    return _withdrawCollateralWithETH(msg.sender, amount);
  }
    
  /// @notice Users call this to withdraw mToken collateral, where their
  /// collateral is automatically unwrapped into ETH for convenience.
  /// @param amount Amount to withdraw (in WETH local currency)
  /// @return uint New collateral balance (in MToken balance)
  function withdrawCollateralWithMTokenWrapWithETH(uint amount) external nonReentrant whenNotPaused(102) returns(uint) {
    IWETH weth = IWETH(_qAdmin.WETH());
    address mTokenAddress = _qAdmin.underlyingToMToken(weth);
    return _withdrawCollateralWithMTokenUnwrap(msg.sender, mTokenAddress, amount, true);
  }
  
  /** VIEW FUNCTIONS **/

  /// @notice Get the address of the `QAdmin` contract
  /// @return address Address of `QAdmin` contract
  function qAdmin() external view returns(address){
    return address(_qAdmin);
  }

  /// @notice Get the address of the `QPriceOracle` contract
  /// @return address Address of `QPriceOracle` contract
  function qPriceOracle() external view returns(address){
    return address(_qPriceOracle);
  }

  /// @notice Get all enabled `Asset`s
  /// @return address[] iterable list of enabled `Asset`s
  function allAssets() external view returns(address[] memory) {
    return _qAdmin.allAssets();
  }
  
  /// @notice Gets the `CollateralFactor` associated with a ERC20 token
  /// @param token ERC20 token
  /// @return uint Collateral Factor, scaled by 1e8
  function collateralFactor(IERC20 token) external view returns(uint) {
    return _qAdmin.collateralFactor(token);
  }

  /// @notice Gets the `MarketFactor` associated with a ERC20 token
  /// @param token ERC20 token
  /// @return uint Market Factor, scaled by 1e8
  function marketFactor(IERC20 token) external view returns(uint) {
    return _qAdmin.marketFactor(token);
  }
  
  /// @notice Return what the collateral ratio for an account would be
  /// with a hypothetical collateral withdraw/deposit and/or token borrow/lend.
  /// The collateral ratio is calculated as:
  /// (`virtualCollateralValue` / `virtualBorrowValue`)
  /// If the returned value falls below 1e8, the account can be liquidated
  /// @param account User account
  /// @param hypotheticalToken Currency of hypothetical withdraw / deposit
  /// @param withdrawAmount Amount of hypothetical withdraw in local currency
  /// @param depositAmount Amount of hypothetical deposit in local currency
  /// @param hypotheticalMarket Market of hypothetical borrow
  /// @param borrowAmount Amount of hypothetical borrow in local ccy
  /// @param lendAmount Amount of hypothetical lend in local ccy
  /// @return uint Hypothetical collateral ratio
  function hypotheticalCollateralRatio(
                                       address account,
                                       IERC20 hypotheticalToken,
                                       uint withdrawAmount,
                                       uint depositAmount,
                                       IFixedRateMarket hypotheticalMarket,
                                       uint borrowAmount,
                                       uint lendAmount
                                       ) external view returns(uint){
    return _getHypotheticalCollateralRatio(
                                           account,
                                           hypotheticalToken,
                                           withdrawAmount,
                                           depositAmount,
                                           hypotheticalMarket,
                                           borrowAmount,
                                           lendAmount
                                           );
  }

  /// @notice Return the current collateral ratio for an account.
  /// The collateral ratio is calculated as:
  /// (`virtualCollateralValue` / `virtualBorrowValue`)
  /// If the returned value falls below 1e8, the account can be liquidated
  /// @param account User account
  /// @return uint Collateral ratio
  function collateralRatio(address account) public view returns(uint){
    return _getHypotheticalCollateralRatio(
                                           account,
                                           IERC20(NULL),
                                           0,
                                           0,
                                           IFixedRateMarket(NULL),
                                           0,
                                           0
                                           );
  }

  /// @notice Get the `collateralFactor` weighted value (in USD) of all the
  /// collateral deposited for an account
  /// @param account Account to query
  /// @return uint Total value of account in USD, scaled to 1e18
  function virtualCollateralValue(address account) public view returns(uint){
    return _getHypotheticalCollateralValue(account, IERC20(NULL), 0, 0, true);
  }

  /// @notice Get the `collateralFactor` weighted value (in USD) for the tokens
  /// deposited for an account
  /// @param account Account to query
  /// @param token ERC20 token
  /// @return uint Value of token collateral of account in USD, scaled to 1e18
  function virtualCollateralValueByToken(
                                         address account,
                                         IERC20 token
                                         ) external view returns(uint){
    return _getHypotheticalCollateralValueByToken(account, token, 0, 0, true);
  }

  /// @notice Return what the weighted total borrow value for an account would be with a hypothetical borrow  
  /// @param account Account to query
  /// @param hypotheticalMarket Market of hypothetical borrow / lend
  /// @param borrowAmount Amount of hypothetical borrow in local ccy
  /// @param lendAmount Amount of hypothetical lend in local ccy
  /// @return uint Borrow value of account in USD, scaled to 1e18
  function hypotheticalVirtualBorrowValue(
                                          address account,
                                          IFixedRateMarket hypotheticalMarket,
                                          uint borrowAmount,
                                          uint lendAmount
                                          ) external view returns(uint){
    return _getHypotheticalBorrowValue(account, hypotheticalMarket, borrowAmount, lendAmount, true);
  }

  /// @notice Get the `marketFactor` weighted net borrows (i.e. borrows - lends)
  /// in USD summed across all `Market`s participated in by the user
  /// @param account Account to query
  /// @return uint Borrow value of account in USD, scaled to 1e18
  function virtualBorrowValue(address account) public view returns(uint){
    return _getHypotheticalBorrowValue(account, IFixedRateMarket(NULL), 0, 0, true);
  }

  /// @notice Get the `marketFactor` weighted net borrows (i.e. borrows - lends)
  /// in USD for a particular `Market`
  /// @param account Account to query
  /// @param market `FixedRateMarket` contract
  /// @return uint Borrow value of account in USD, scaled to 1e18
  function virtualBorrowValueByMarket(
                                      address account,
                                      IFixedRateMarket market
                                      ) external view returns(uint){
    return _getHypotheticalBorrowValueByMarket(account, market, 0, 0, true);
  }
  
  /// @notice Get the unweighted value (in USD) of all the collateral deposited
  /// for an account
  /// @param account Account to query
  /// @return uint Total value of account in USD, scaled to 1e18
  function realCollateralValue(address account) external view returns(uint){
    return _getHypotheticalCollateralValue(account, IERC20(NULL), 0, 0, false);
  }
  
  /// @notice Get the unweighted value (in USD) of the tokens deposited
  /// for an account
  /// @param account Account to query
  /// @param token ERC20 token
  /// @return uint Value of token collateral of account in USD, scaled to 1e18
  function realCollateralValueByToken(
                                      address account,
                                      IERC20 token
                                      ) external view returns(uint){
    return _getHypotheticalCollateralValueByToken(account, token, 0, 0, false);
  }
  
  /// @notice Get the unweighted current net value borrowed (i.e. borrows - lends)
  /// in USD summed across all `Market`s participated in by the user
  /// @param account Account to query
  /// @return uint Borrow value of account in USD, scaled to 1e18
  function realBorrowValue(address account) external view returns(uint){
    return _getHypotheticalBorrowValue(account, IFixedRateMarket(NULL), 0, 0, false);
  }

  /// @notice Get the unweighted current net value borrowed (i.e. borrows - lends)
  /// in USD for a particular `Market`
  /// @param account Account to query
  /// @param market `FixedRateMarket` contract
  /// @return uint Borrow value of account in USD, scaled to 1e18
  function realBorrowValueByMarket(
                                   address account,
                                   IFixedRateMarket market
                                   ) external view returns(uint){
    return _getHypotheticalBorrowValueByMarket(account, market, 0, 0, false);
  }
  
  /// @notice Get an account's maximum available borrow amount in a specific FixedRateMarket.
  /// For example, what is the maximum amount of GLMRJUL22 that an account can borrow
  /// while ensuring their account health continues to be acceptable?
  /// Note: This function will return 0 if market to borrow is disabled
  /// Note: This function will return creditLimit() if maximum amount allowed for one market exceeds creditLimit()
  /// Note: User can only borrow up to `initCollateralRatio` for their own protection against instant liquidations
  /// @param account User account
  /// @param borrowMarket Address of the `FixedRateMarket` market to borrow
  /// @return uint Maximum available amount user can borrow (in FV) without breaching `initCollateralRatio`
  function hypotheticalMaxBorrowFV(address account, IFixedRateMarket borrowMarket) external view returns(uint) {
    IERC20 borrowERC20 = borrowMarket.underlyingToken();
    QTypes.Asset memory asset = _qAdmin.assets(borrowERC20);
    uint currentRatio = collateralRatio(account);
    uint initRatio = _qAdmin.initCollateralRatio(account);
    if (currentRatio <= initRatio) {
      return 0;
    }
    uint creditLimit = _qAdmin.creditLimit(account);
    // initCollateralRatio = virtualCollateralValue / (virtualBorrowValue + virtualMaxBorrowFV) 
    // => virtualMaxBorrowFV = virtualCollateralValue / initCollateralRatio - virtualBorrowValue
    uint virtualCollateral = virtualCollateralValue(account);
    uint virtualBorrow = virtualBorrowValue(account);
    uint virtualUSD = (virtualCollateral * _qAdmin.MANTISSA_COLLATERAL_RATIO() / initRatio) - virtualBorrow;
    if (virtualUSD > creditLimit) {
      // borrow value should not breach credit limit
      virtualUSD = creditLimit;
    }
    uint realUSD = virtualUSD * asset.marketFactor / _qAdmin.MANTISSA_FACTORS();
    uint valueLocal = _qPriceOracle.USDToLocal(borrowERC20, realUSD);
    uint marketLocalLend = _qTokenBalance(borrowMarket, account);
    
    // qToken can also be counted towards borrowable amount    
    return valueLocal + marketLocalLend;
  }
  
  /// @notice Get the minimum collateral ratio. Scaled by 1e8.
  /// @return uint Minimum collateral ratio
  function minCollateralRatio() external view returns(uint){
    return _qAdmin.minCollateralRatio(msg.sender);
  }
  
  /// @notice Get the minimum collateral ratio for a user account. Scaled by 1e8.
  /// @param account User account 
  /// @return uint Minimum collateral ratio
  function minCollateralRatio(address account) external view returns(uint){
    return _qAdmin.minCollateralRatio(account);
  }

  /// @notice Get the initial collateral ratio. Scaled by 1e8
  /// @return uint Initial collateral ratio
  function initCollateralRatio() external view returns(uint){
    return _qAdmin.initCollateralRatio(msg.sender);
  }
  
  /// @notice Get the initial collateral ratio for a user account. Scaled by 1e8
  /// @param account User account 
  /// @return uint Initial collateral ratio
  function initCollateralRatio(address account) external view returns(uint){
    return _qAdmin.initCollateralRatio(account);
  }

  /// @notice Get the close factor. Scaled by 1e8
  /// @return uint Close factor
  function closeFactor() external view returns(uint){
    return _qAdmin.closeFactor();
  }

  /// @notice Get the liquidation incentive. Scaled by 1e8
  /// @return uint Liquidation incentive
  function liquidationIncentive() external view returns(uint){
    return _qAdmin.liquidationIncentive();
  }

  /// @notice Use this for quick lookups of collateral balances by asset
  /// @param account User account  
  /// @param token ERC20 token
  /// @return uint Balance in local
  function collateralBalance(address account, IERC20 token) external view returns(uint){
    return _collateralBalances[account][token];
  }

  /// @notice Get iterable list of collateral addresses which an account has nonzero balance.
  /// @param account User account
  /// @return address[] Iterable list of ERC20 token addresses
  function iterableCollateralAddresses(address account) external view returns(IERC20[] memory){
    return _iterableCollateralAddresses[account];
  }

  /// @notice Quick lookup of whether an account has a particular collateral
  /// @param account User account
  /// @param token ERC20 token addresses
  /// @return bool True if account has collateralized with given ERC20 token, false otherwise
  function accountCollateral(address account, IERC20 token) external view returns(bool) {
    return _accountCollateral[account][token];
  }
  
  /// @notice Get iterable list of all Markets which an account has participated
  /// @param account User account
  /// @return address[] Iterable list of `FixedRateLoanMarket` contract addresses
  function iterableAccountMarkets(address account) external view returns(IFixedRateMarket[] memory){
    return _iterableAccountMarkets[account];
  }

  /// @notice Quick lookup of whether an account has participated in a Market
  /// @param account User account
  /// @param market`FixedRateLoanMarket` contract
  /// @return bool True if participated, false otherwise
  function accountMarkets(address account, IFixedRateMarket market) external view returns(bool){
    return _accountMarkets[account][market];
  }

  /// @notice Converts any local value into its value in USD using oracle feed price
  /// @param token ERC20 token
  /// @param amountLocal Amount denominated in terms of the ERC20 token
  /// @return uint Amount in USD, scaled to 1e18
  function localToUSD(
                      IERC20 token,
                      uint amountLocal
                      ) external view returns(uint){
    return _qPriceOracle.localToUSD(token, amountLocal);
  }

  /// @notice Converts any value in USD into its value in local using oracle feed price
  /// @param token ERC20 token
  /// @param valueUSD Amount in USD
  /// @return uint Amount denominated in terms of the ERC20 token
  function USDToLocal(
                      IERC20 token,
                      uint valueUSD
                      ) external view returns(uint){
    return _qPriceOracle.USDToLocal(token, valueUSD);
  }
  
  /** INTERNAL FUNCTIONS **/

  /// @notice Return what the collateral ratio for an account would be
  /// with a hypothetical collateral withdraw and/or token borrow.
  /// The collateral ratio is calculated as:
  /// (`virtualCollateralValue` / `virtualBorrowValue`)
  /// If the returned value falls below 1e8, the account can be liquidated
  /// @param account User account
  /// @param hypotheticalToken Currency of hypothetical withdraw / deposit
  /// @param withdrawAmount Amount of hypothetical withdraw in local currency
  /// @param depositAmount Amount of hypothetical deposit in local currency
  /// @param hypotheticalMarket Market of hypothetical borrow / lend
  /// @param borrowAmount Amount of hypothetical borrow in local ccy
  /// @param lendAmount Amount of hypothetical lend in local ccy
  /// @return uint Hypothetical collateral ratio
  function _getHypotheticalCollateralRatio(
                                           address account,
                                           IERC20 hypotheticalToken,
                                           uint withdrawAmount,
                                           uint depositAmount,
                                           IFixedRateMarket hypotheticalMarket,
                                           uint borrowAmount,
                                           uint lendAmount
                                           ) internal view returns(uint){
    
    // The numerator is the weighted hypothetical collateral value
    uint num = _getHypotheticalCollateralValue(
                                               account,
                                               hypotheticalToken,
                                               withdrawAmount,
                                               depositAmount,
                                               true
                                               );

    // The denominator is the weighted hypothetical borrow value
    uint denom = _getHypotheticalBorrowValue(
                                             account,
                                             hypotheticalMarket,
                                             borrowAmount,
                                             lendAmount,
                                             true
                                             );

    if(denom == 0){
      // Need to handle division by zero if account has no borrows
      return _qAdmin.UINT_MAX();      
    }else{
      // Return the collateral  ratio as a value from 0-1, scaled by 1e8
      return num * _qAdmin.MANTISSA_COLLATERAL_RATIO() / denom;
    }        
  }

  /// @notice Return what the total collateral value for an account would be
  /// with a hypothetical withdraw, with an option for weighted or unweighted value
  /// @param account Account to query
  /// @param hypotheticalToken Currency of hypothetical withdraw / deposit
  /// @param withdrawAmount Amount of hypothetical withdraw in local currency
  /// @param depositAmount Amount of hypothetical deposit in local currency
  /// @param applyCollateralFactor True to get the `collateralFactor` weighted value, false otherwise
  /// @return uint Total value of account in USD, scaled to 1e18
  function _getHypotheticalCollateralValue(
                                           address account,
                                           IERC20 hypotheticalToken,
                                           uint withdrawAmount,
                                           uint depositAmount,
                                           bool applyCollateralFactor
                                           ) internal view returns(uint){
            
    uint totalValueUSD = 0;

    // If user has never deposited collateral in `hypotheticalToken` before, it
    // will not be included in `_iterableCollateralAddresses` by default, so
    // it needs to be handled separately
    uint newTokenOffset = _qAdmin.assets(hypotheticalToken).isEnabled && !_accountCollateral[account][hypotheticalToken] ? 1 : 0;
    uint collateralAddressesLength = _iterableCollateralAddresses[account].length;

    for (uint i = 0; i < collateralAddressesLength + newTokenOffset;) {

      // Get the token address in i'th slot of `_iterableCollateralAddresses[account]`
      // or else the `hypotheticalToken` if it is not included in `iterableColalteralAddresses`
      IERC20 token = i < collateralAddressesLength ? _iterableCollateralAddresses[account][i] : hypotheticalToken;

      // Check if token address matches token in target
      if(address(token) == address(hypotheticalToken)){
        // Add value to total adjusted by hypothetical deposit / withdraw amount
        totalValueUSD += _getHypotheticalCollateralValueByToken(
                                                                account,
                                                                hypotheticalToken,
                                                                withdrawAmount,
                                                                depositAmount,
                                                                applyCollateralFactor
                                                                );
      }else{
        // Add value to total without adjustment
        totalValueUSD += _getHypotheticalCollateralValueByToken(
                                                                account,
                                                                token,
                                                                0,
                                                                0,
                                                                applyCollateralFactor
                                                                );
      }
      unchecked { i++; }
    }
    
    return totalValueUSD;
  }

  /// @notice Return what the collateral value by token for an account would be
  /// with a hypothetical withdraw, with an option for weighted or unweighted value
  /// @param account Account to query
  /// @param token ERC20 token
  /// @param withdrawAmount Amount of hypothetical withdraw in local currency
  /// @param depositAmount Amount of hypothetical deposit in local currency
  /// @param applyCollateralFactor True to get the `collateralFactor` weighted value, false otherwise
  /// @return uint Total value of account in USD, scaled to 1e18
  function _getHypotheticalCollateralValueByToken(
                                                  address account,
                                                  IERC20 token,
                                                  uint withdrawAmount,
                                                  uint depositAmount,
                                                  bool applyCollateralFactor
                                                  ) internal view returns(uint){

    // Withdraw amount must be less than collateral balance
    if (withdrawAmount > _collateralBalances[account][token]) {
      revert CustomErrors.QM_WithdrawMoreThanCollateral();
    }
    
    // Get the `Asset` associated to this token
    QTypes.Asset memory asset = _qAdmin.assets(token);

    // Value of collateral in any unsupported `Asset` is zero
    if(!asset.isEnabled){
      return 0;
    }
    
    // Get the local balance of the account for the given `token`
    uint balanceLocal = _collateralBalances[account][token];

    // Adjust by hypothetical withdraw / deposit amount. Guaranteed not to underflow
    balanceLocal = balanceLocal + depositAmount - withdrawAmount;
    
    // Convert the local balance to USD
    uint valueUSD = _qPriceOracle.localToUSD(token, balanceLocal);
    
    if(applyCollateralFactor){
      // Apply the `collateralFactor` to get the discounted value of the asset       
      valueUSD = valueUSD * asset.collateralFactor / _qAdmin.MANTISSA_FACTORS();
    }
    
    return valueUSD;
  }

  /// @notice Return what the total borrow value for an account would be
  /// with a hypothetical borrow, with an option for weighted or unweighted value  
  /// @param account Account to query
  /// @param hypotheticalMarket Market of hypothetical borrow / lend
  /// @param borrowAmount Amount of hypothetical borrow in local ccy
  /// @param lendAmount Amount of hypothetical lend in local ccy
  /// @param applyMarketFactor True to get the `marketFactor` weighted value, false otherwise
  /// @return uint Borrow value of account in USD, scaled to 1e18
  function _getHypotheticalBorrowValue(
                                       address account,
                                       IFixedRateMarket hypotheticalMarket,
                                       uint borrowAmount,
                                       uint lendAmount,
                                       bool applyMarketFactor
                                       ) internal view returns(uint){
    uint totalValueUSD = 0;
    
    // If user has never entered `hypotheticalMarket` before, it will not be
    // included in `_iterableAccountMarkets` by default, so it needs to be
    // handled separately
    uint newMarketOffset = _qAdmin.isMarketEnabled(address(hypotheticalMarket)) && !_accountMarkets[account][hypotheticalMarket] ? 1 : 0;
    uint accountMarketsLength = _iterableAccountMarkets[account].length;
    
    for (uint i = 0; i < accountMarketsLength + newMarketOffset;) {
      
      // Get the market address in i'th slot of `_iterableAccountMarkets[account]`
      IFixedRateMarket market = i < accountMarketsLength ? _iterableAccountMarkets[account][i] : hypotheticalMarket;
      
      // Check if the user is requesting to borrow more in this `Market`
      if(address(market) == address(hypotheticalMarket)){
        // User requesting to borrow / lend in this `Market`, adjust amount accordingly
        totalValueUSD += _getHypotheticalBorrowValueByMarket(
                                                             account,
                                                             hypotheticalMarket,
                                                             borrowAmount,
                                                             lendAmount,
                                                             applyMarketFactor
                                                             );
      }else{
        // User not requesting to borrow more in this `Market`, just get current value
        totalValueUSD += _getHypotheticalBorrowValueByMarket(
                                                             account,   
                                                             market,
                                                             0,
                                                             0,
                                                             applyMarketFactor
                                                             );
      }
      unchecked { i++; }
    }
    return totalValueUSD;    
  }

  /// @notice Return what the borrow value by `Market` for an account would be
  /// with a hypothetical borrow, with an option for weighted or unweighted value  
  /// @param account Account to query
  /// @param market Market of the hypothetical borrow / lend
  /// @param borrowAmount Amount of hypothetical borrow in local ccy
  /// @param lendAmount Amount of hypothetical lend in local ccy
  /// @param applyMarketFactor True to get the `marketFactor` weighted value, false otherwise
  /// @return uint Borrow value of account in USD (18 decimal places)
  function _getHypotheticalBorrowValueByMarket(
                                               address account,
                                               IFixedRateMarket market,
                                               uint borrowAmount,
                                               uint lendAmount,
                                               bool applyMarketFactor
                                               ) internal view returns(uint){
    
    // Total `borrowsLocal` should be current borrow plus `borrowAmount`
    uint borrowsLocal = market.accountBorrows(account) + borrowAmount;

    // Total `lendsLocal` should be user's balance of qTokens plus `lendAmount`
    uint lendsLocal = _qTokenBalance(market, account) + lendAmount;
    if(lendsLocal >= borrowsLocal){
      // Default to zero if lends greater than borrows
      return 0;
    }else{
      
      // Get the net amount being borrowed in local
      // Guaranteed not to underflow from the above check
      uint borrowValueLocal = borrowsLocal - lendsLocal;     

      // Convert from local value to value in USD
      IERC20 token = market.underlyingToken();
      QTypes.Asset memory asset = _qAdmin.assets(token);
      uint borrowValueUSD = _qPriceOracle.localToUSD(token, borrowValueLocal);

      if(applyMarketFactor){
        // Apply the `marketFactor` to get the risk premium value of the borrow
        borrowValueUSD = borrowValueUSD * _qAdmin.MANTISSA_FACTORS() / asset.marketFactor;
      }
      
      return borrowValueUSD;
    }
  }
  
  /// @notice Returns qToken balance for given account
  /// @param market Market where qToken balance is to be fetched
  /// @param account Account to fetch qToken balance
  /// @return uint qToken balance for given account;
  function _qTokenBalance(IFixedRateMarket market, address account) internal view returns(uint) {
    IQToken qToken = IQToken(market.qToken());
    return qToken.balanceOf(account);
  }

  /// @notice Users call this to deposit collateral to fund their borrows
  /// @param account Address of user
  /// @param token ERC20 token
  /// @param amount Amount to deposit (in local ccy)
  /// @return uint New collateral balance
  function _depositCollateral(address account, IERC20 token, uint amount) internal returns(uint) {
    // Amount must be positive
    if (amount <= 0) {
      revert CustomErrors.QM_ZeroDepositAmount();
    }
    
    // Transfer the collateral from the account to this contract
    uint balanceBefore = token.balanceOf(address(this));
    token.safeTransferFrom(account, address(this), amount);
    uint balanceAfter = token.balanceOf(address(this));

    // Get more accurate amount of user deposit
    uint actualDeposit = balanceAfter - balanceBefore;    
    
    // Update internal account collateral balance mappings
    _addCollateral(account, token, actualDeposit);
        
    // Return the account's updated collateral balance for this token
    return _collateralBalances[account][token];
  }

  /// @notice Users call this to deposit collateral to fund their borrows, where their
  /// collateral is automatically wrapped into MTokens for convenience so users can
  /// automatically earn interest on their collateral.
  /// @param account Address of the user
  /// @param underlying Underlying ERC20 token
  /// @param amount Amount to deposit (in underlying local currency)
  /// @param isPaidInETH Is amount being paid in ETH
  /// @return uint New collateral balance (in MToken balance)
  function _depositCollateralWithMTokenWrap(
                                            address account,
                                            IERC20 underlying,
                                            uint amount,
                                            bool isPaidInETH
                                            ) internal returns(uint) {
    // Amount must be positive
    if (amount <= 0) {
      revert CustomErrors.QM_ZeroDepositAmount();
    }

    // Get the address of the corresponding MToken
    address mTokenAddress = _qAdmin.underlyingToMToken(underlying);
    
    // Check that the MToken asset has been enabled as collateral
    if (mTokenAddress == address(0)) {
      revert CustomErrors.QM_MTokenUnsupported();
    }
      
    // Get accurate amount of user deposit
    uint actualDepositUnderlying = msg.value;
      
    if (!isPaidInETH) {
      uint balanceBeforeUnderlying = underlying.balanceOf(address(this));
        
      // Transfer the underlying collateral from the account to this contract
      underlying.safeTransferFrom(account, address(this), amount);
        
      // Update user deposit balance for ERC20
      actualDepositUnderlying = underlying.balanceOf(address(this)) - balanceBeforeUnderlying;
    }
    
    if (address(underlying) == _qAdmin.WETH()) {
      // If ERC20 is sent instead of native token, unwrap it first before mint 
      // operation can be called
      if (!isPaidInETH) {
          
        IWETH weth = IWETH(_qAdmin.WETH());
        weth.withdraw(actualDepositUnderlying);
          
      }
        
      // Hardcode special logic for native token ERC20
      // Moonwell uses the Compound-style transferring of native token
      // so we must follow a different interface
      MGlimmerInterface mToken = MGlimmerInterface(mTokenAddress);

      // Forward user collateral to MToken
      uint balanceBeforeMToken = mToken.balanceOf(address(this));
      mToken.mint{value: actualDepositUnderlying}();

      // Get accurate amount of MToken minted
      uint actualDepositMToken = mToken.balanceOf(address(this)) - balanceBeforeMToken;

      // Update internal account collateral balance mappings
      _addCollateral(account, mToken, actualDepositMToken);

      return _collateralBalances[account][mToken];
      
    } else {
      // Make underlying token approval
      // NOTE: This "approve" call should be safe as it only approves the bare
      // minimum transferred, but in general be careful of attacks here. We are
      // relying on the above "require" check that `mTokenAddress` is a safe
      // address, so we should make sure that only admin is able to add
      // `mTokenAddress` as a whitelisted address or else an attacker can
      // potentially drain funds
      underlying.safeApprove(mTokenAddress, 0);
      underlying.safeApprove(mTokenAddress, actualDepositUnderlying);
      
      // Generic logic for all other ERC20 tokens using
      // ERC20 transfer function
      MErc20Interface mToken = MErc20Interface(mTokenAddress);

      // Forward user collateral to MToken and make sure mint is successful 
      uint balanceBeforeMToken = mToken.balanceOf(address(this));
      if (mToken.mint(actualDepositUnderlying) > 0) {
        revert CustomErrors.QA_FailToMintMTokens();
      }

      // Get accurate amount of mTokens minted
      uint actualDepositMToken = mToken.balanceOf(address(this)) - balanceBeforeMToken;

      // Update internal account collateral balance mappings
      _addCollateral(account, mToken, actualDepositMToken);

      return _collateralBalances[account][mToken];      
    }
    
  }
  
  /// @notice Users call this to deposit collateral to fund their borrows, where their
  /// collateral is automatically wrapped from ETH to WETH.
  /// @param account Address of the user
  /// @param amount Amount to deposit (in WETH local currency)
  /// @return uint New collateral balance (in WETH balance)
  function _depositCollateralWithETH(address account, uint amount) internal returns(uint) {
    IWETH weth = IWETH(_qAdmin.WETH());
    
    // Wrap ETH into WETH
    weth.deposit{ value: amount }();

    // Update internal account collateral balance mappings
    _addCollateral(account, weth, amount);

    // Return the account's updated collateral balance for this token
    return _collateralBalances[account][weth];
  }
    
  // User sends 10 ETH --> wrap it into METH and deposit
  
  /// @notice Users call this to withdraw collateral
  /// @param account Address of user
  /// @param token ERC20 token
  /// @param amount Amount to withdraw (in local ccy)
  /// @return uint New collateral balance 
  function _withdrawCollateral(address account, IERC20 token, uint amount) internal returns(uint) {
    
    // Amount must be positive
    if (amount <= 0) {
      revert CustomErrors.QM_ZeroWithdrawAmount();
    }
    
    // Get the hypothetical collateral ratio after withdrawal
    uint collateralRatio_ = _getHypotheticalCollateralRatio(
                                                            account,
                                                            token,
                                                            amount,
                                                            0,
                                                            IFixedRateMarket(NULL),
                                                            0,
                                                            0
                                                            );

    // Check that the `collateralRatio` after withdrawal is still healthy.
    // User is only allowed to withdraw up to `_initCollateralRatio`, not
    // `_minCollateralRatio`, for their own protection against instant liquidations.
    if (collateralRatio_ < _qAdmin.initCollateralRatio(account)) {
      revert CustomErrors.QM_InvalidWithdrawal(collateralRatio_, _qAdmin.initCollateralRatio(account));
    }

    // Update internal account collateral balance mappings
    _subtractCollateral(account, token, amount);

    // Send collateral from the protocol to the account
    token.safeTransfer(account, amount);

    // Emit the event
    emit WithdrawCollateral(account, address(token), amount);

    // Return the account's updated collateral balance for this token
    return _collateralBalances[account][token];
  }

  /// @notice Users call this to withdraw mToken collateral, where their
  /// collateral is automatically unwrapped into underlying tokens for
  /// convenience.
  /// @param account Address of the user
  /// @param mTokenAddress Yield-bearing token address
  /// @param amount Amount to withdraw (in mToken local currency)
  /// @param isPaidInETH Is amount being paid in ETH
  /// @return uint New collateral balance (in MToken balance)
  function _withdrawCollateralWithMTokenUnwrap(
                                               address account,
                                               address mTokenAddress,
                                               uint amount,
                                               bool isPaidInETH
                                               ) internal returns(uint) {
    // Amount must be positive
    if (amount <= 0) {
      revert CustomErrors.QM_ZeroWithdrawAmount();
    }
      
    // Get the hypothetical collateral ratio after withdrawal
    uint collateralRatio_ = _getHypotheticalCollateralRatio(
                                                            account,
                                                            IERC20(mTokenAddress),
                                                            amount,
                                                            0,
                                                            IFixedRateMarket(NULL),
                                                            0,
                                                            0
                                                            );

    // Check that the `collateralRatio` after withdrawal is still healthy.
    // User is only allowed to withdraw up to `_initCollateralRatio`, not
    // `_minCollateralRatio`, for their own protection against instant liquidations.
    if (collateralRatio_ < _qAdmin.initCollateralRatio(account)) {
      revert CustomErrors.QM_InvalidWithdrawal(collateralRatio_, _qAdmin.initCollateralRatio(account));
    }
    
    // Get the corresponding underlying
    address underlyingAddress = _qAdmin.assets(IERC20(mTokenAddress)).underlying;
    IERC20 underlying = IERC20(underlyingAddress);
    uint actualAmountUnderlying = 0;
    
    if (underlyingAddress == _qAdmin.WETH()) {
      // Hardcode special logic for native token ERC20
      // Moonwell uses the Compound-style transferring of native token
      // so we must follow a different interface
      MGlimmerInterface mToken = MGlimmerInterface(mTokenAddress);

      // Redeem mTokens for underlying, make sure it is successful and return it to user
      uint balanceBeforeNative = address(this).balance;
      if (mToken.redeem(amount) > 0) {
        revert CustomErrors.QA_FailToRedeemMTokens();
      }
      
      // Get accurate amount of native token redeemed
      actualAmountUnderlying = address(this).balance - balanceBeforeNative;
      
      // Update internal account collateral balance mappings
      _subtractCollateral(account, mToken, amount);
      
    } else {
      // Generic logic for all other ERC20 tokens using
      // ERC20 transfer function
      MErc20Interface mToken = MErc20Interface(mTokenAddress);

      // Redeem mTokens for underlying, make sure it is successful and return it to user
      uint balanceBeforeUnderlying = underlying.balanceOf(address(this));
      if (mToken.redeem(amount) > 0) {
        revert CustomErrors.QA_FailToRedeemMTokens();
      }
      
      // Get accurate amount of underlying redeemed
      actualAmountUnderlying = underlying.balanceOf(address(this)) - balanceBeforeUnderlying;

      // Update internal account collateral balance mappings
      _subtractCollateral(account, mToken, amount);
      
    }
      
    if (isPaidInETH) {
      // Underlying address must be WETH if withdrawal is to be paid in ETH
      // So just sent native token to user directly
      (bool success,) = msg.sender.call{ value: actualAmountUnderlying }("");
      if (!success) {
        revert CustomErrors.QM_UnsuccessfulEthTransfer();
      }
      
    } else {
      // If underlying is WETH but withdrawal is not paid in ETH
      // Needs to wrap native token before sending to user
      if (underlyingAddress == _qAdmin.WETH()) {
          
        IWETH weth = IWETH(_qAdmin.WETH());
        weth.deposit{ value: actualAmountUnderlying }();
        
      }
      
      // Send underlying collateral from the protocol to the account
      underlying.safeTransfer(account, actualAmountUnderlying);
      
    }

    // Emit the event
    emit WithdrawCollateral(account, mTokenAddress, amount);
    
    return _collateralBalances[account][IERC20(mTokenAddress)];
  }

  /// @notice Users call this to withdraw ETH collateral, where their
  /// collateral is automatically unwrapped from WETH for convenience.
  /// @param account Address of the user
  /// @param amount Amount to withdraw (in currency of WETH)
  /// @return uint New collateral balance (in WETH balance)
  function _withdrawCollateralWithETH(address account, uint amount) internal returns(uint) {
    IWETH weth = IWETH(_qAdmin.WETH());
    
    // Amount must be positive
    if (amount <= 0) {
      revert CustomErrors.QM_ZeroWithdrawAmount();
    }
    
    // Get the hypothetical collateral ratio after withdrawal
    uint collateralRatio_ = _getHypotheticalCollateralRatio(
                                                            account,
                                                            weth,
                                                            amount,
                                                            0,
                                                            IFixedRateMarket(NULL),
                                                            0,
                                                            0
                                                            );

    // Check that the `collateralRatio` after withdrawal is still healthy.
    // User is only allowed to withdraw up to `_initCollateralRatio`, not
    // `_minCollateralRatio`, for their own protection against instant liquidations.
    if (collateralRatio_ < _qAdmin.initCollateralRatio(account)) {
      revert CustomErrors.QM_InvalidWithdrawal(collateralRatio_, _qAdmin.initCollateralRatio(account));
    }

    // Update internal account collateral balance mappings
    _subtractCollateral(account, weth, amount);

    // Unwrap WETH
    weth.withdraw(amount);
    
    // Send collateral from the protocol to the account
    (bool success,) = account.call{value: amount}("");
    if (!success) {
      revert CustomErrors.QM_UnsuccessfulEthTransfer();
    }

    // Emit the event
    emit WithdrawCollateral(account, address(0), amount);

    // Return the account's updated collateral balance for this token
    return _collateralBalances[account][weth];
  }
  
  /// @notice Add to internal account collateral balance and related mappings
  /// @param account User account
  /// @param token Currency which the collateral will be denominated in
  /// @param amount Amount to add
  function _addCollateral(address account, IERC20 token, uint amount) internal{

    // Get the associated `Asset` to the token address
    QTypes.Asset memory asset = _qAdmin.assets(token);

    // Only enabled assets are supported as collateral
    if (!asset.isEnabled) {
      revert CustomErrors.QM_AssetNotSupported();
    }

    // Record that sender now has collateral deposited in this currency
    // This should only be updated once per account when initially depositing
    // collateral in a new currency to ensure that the `_accountCollateral` mapping
    // remains unique
    if(!_accountCollateral[account][token]){
      _iterableCollateralAddresses[account].push(token);
      _accountCollateral[account][token] = true;
    }

    // Record the increase in collateral balance for the account
    _collateralBalances[account][token] += amount;

    // Emit the event
    emit DepositCollateral(account, address(token), amount);
  }

  /// @notice Subtract from internal account collateral balance and related mappings
  /// @param account User account
  /// @param token Currency which the collateral will be denominated in
  /// @param amount Amount to subtract
  function _subtractCollateral(address account, IERC20 token, uint amount) internal{

    // Check that user has enough collateral to be subtracted
    if (_collateralBalances[account][token] < amount) {
      revert CustomErrors.QM_NotEnoughCollateral();
    }
    
    // Record the decrease in collateral balance for the account
    _collateralBalances[account][token] -= amount;
  }

}

