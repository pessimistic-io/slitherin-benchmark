//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./Initializable.sol";
import "./IERC20.sol";
import "./IERC20Metadata.sol";
import "./AggregatorV3Interface.sol";
import "./IDIAOracleV2.sol";
import "./MTokenInterfaces.sol";
import "./IQAdmin.sol";
import "./IQPriceOracle.sol";
import "./CustomErrors.sol";
import "./QTypes.sol";

contract QPriceOracle is Initializable, IQPriceOracle {
  
  /// @notice Reserve storage gap so introduction of new parent class later on can be done via upgrade
  uint256[50] __gap;

  /// @notice Contract storing all global Qoda parameters
  IQAdmin private _qAdmin;

  /// @notice Address of DIA Oracle
  IDIAOracleV2 private _DIAOracle;
  
  /// @notice Constructor for upgradeable contracts
  /// @param qAdminAddress_ Address of the `QAdmin` contract
  function initialize(address qAdminAddress_) public initializer {
    _qAdmin = IQAdmin(qAdminAddress_);
  }

  modifier onlyAdmin() {
    if(!_qAdmin.hasRole(_qAdmin.ADMIN_ROLE(), msg.sender)) {
      revert CustomErrors.QPO_OnlyAdmin();
    }
    _;
  }

  /** ADMIN/RESTRICTED FUNCTIONS **/
  
  function _setDIAOracle(address DIAOracleAddr) external onlyAdmin() {

    // Only allow oracle set once
    if(address(_DIAOracle) != address(0)) {
      revert CustomErrors.QPO_Already_Set();
    }
    
    _DIAOracle = IDIAOracleV2(DIAOracleAddr);

    // Emit the event
    emit SetDIAOracle(DIAOracleAddr);
  }
  
  /** VIEW FUNCTIONS **/
  
  /// @notice Converts any local value into its value in USD using oracle feed price
  /// @param token ERC20 token
  /// @param amountLocal Amount denominated in terms of the ERC20 token
  /// @return uint Amount in USD (18 digit precision)
  function localToUSD(IERC20 token, uint amountLocal) external view returns(uint){
    return _localToUSD(token, amountLocal);
  }

  /// @notice Converts any value in USD into its value in local using oracle feed price
  /// @param token ERC20 token
  /// @param valueUSD Amount in USD (18 digit precision)
  /// @return uint Amount denominated in terms of the ERC20 token
  function USDToLocal(IERC20 token, uint valueUSD) external view returns(uint){
    return _USDToLocal(token, valueUSD);
  }

  /// @notice Convenience function for getting price feed from various oracles.
  /// Returned prices should ALWAYS be normalized to eight decimal places.
  /// @param underlyingToken Address of the underlying token
  /// @param oracleFeed Address of the oracle feed
  /// @return answer uint256, decimals uint8
  function priceFeed(
                     IERC20 underlyingToken,
                     address oracleFeed
                     ) external view returns(uint256, uint8){
    return _priceFeed(underlyingToken, oracleFeed);
  }

  /// @notice Compound/Moonwell do not provide a view function for retrieving the
  /// current exchange rate between the yield bearing token and the underlying
  /// token. The protocol includes an exchangeRateCurrent() function which gives
  /// the value that we need, but it includes writes to storage, which is not gas
  /// efficient for our usage. Hence, we need this function to manually calculate
  /// the current exchange rate as a view function from the last stored exchange
  /// rate using 1) the interest accrual and 2) exchange rate formulas.
  /// @param mTokenAddress Address of the mToken contract
  function mTokenExchRateCurrent(address mTokenAddress) external view returns(uint){
    return _mTokenExchRateCurrent(mTokenAddress);
  }
  
  /// @notice Get the address of the `QAdmin` contract
  /// @return address Address of `QAdmin` contract
  function qAdmin() external view returns(address){
    return address(_qAdmin);
  }

  /** INTERNAL FUNCTIONS **/
  
  /// @notice Converts any local value into its value in USD using oracle feed price
  /// @param token ERC20 token
  /// @param amountLocal Amount denominated in terms of the ERC20 token
  /// @return uint Amount in USD (18 decimal place precision)
  function _localToUSD(IERC20 token, uint amountLocal) internal view returns(uint){
    
    // Check that the token is an enabled asset
    QTypes.Asset memory asset = _qAdmin.assets(token);
    if (!asset.isEnabled) {
      revert CustomErrors.QPO_AssetNotSupported();
    }

    // Instantiate the underlying token ERC20 with decimal data
    IERC20Metadata underlyingMetadata = IERC20Metadata(asset.underlying);
    
    if(asset.isYieldBearing){
      // If the asset is yield-bearing, we need one extra step first
      // to convert from the amount of yield bearing tokens to
      // the amount of underlying tokens
            
      // mTokenExchRate is value of 1 mToken in underlying token
      uint mTokenExchRate = _mTokenExchRateCurrent(address(token));
      
      // amountUnderlying = mTokenAmount * mTokenExchRate / 10^18
      uint amountUnderlying = amountLocal * mTokenExchRate / (10 ** 18);

      // amountLocal now represents the amount of underlying tokens
      amountLocal = amountUnderlying;
    }
    
    // Get the oracle feed
    address oracleFeed = asset.oracleFeed;    
    (uint exchRate, uint8 exchDecimals) = _priceFeed(IERC20(asset.underlying), oracleFeed);
    
    // Initialize all the necessary mantissas first
    uint exchRateMantissa = 10 ** exchDecimals;
    uint tokenMantissa = 10 ** underlyingMetadata.decimals();
    
    // Apply exchange rate to convert from amount of underlying tokens to value in USD
    uint valueUSD = amountLocal * exchRate * _qAdmin.MANTISSA_USD();
    
    // Divide by mantissas last for maximum precision
    valueUSD = valueUSD / tokenMantissa / exchRateMantissa;
    
    return valueUSD;
  }

  /// @notice Converts any value in USD into its amount in local using oracle feed price.
  /// For yield-bearing tokens, it will convert the value in USD directly into the
  /// amount of yield-bearing token (NOT the amount of underlying token)
  /// @param token ERC20 token
  /// @param valueUSD Amount in USD (18 digit precision)
  /// @return uint Amount denominated in terms of the ERC20 token
  function _USDToLocal(IERC20 token, uint valueUSD) internal view returns(uint){

    // Check that the token is an enabled asset
    QTypes.Asset memory asset = _qAdmin.assets(token);
    if (!asset.isEnabled) {
      revert CustomErrors.QPO_AssetNotSupported();
    }

    // Instantiate the underlying token ERC20 with decimal data
    IERC20Metadata underlyingMetadata = IERC20Metadata(asset.underlying);
    
    // Get the oracle feed
    address oracleFeed = asset.oracleFeed;
    (uint exchRate, uint8 exchDecimals) = _priceFeed(IERC20(asset.underlying), oracleFeed);

    // Initialize all the necessary mantissas first
    uint exchRateMantissa = 10 ** exchDecimals;
    uint tokenMantissa = 10 ** underlyingMetadata.decimals();

    // Multiply by mantissas first for maximum precision
    uint amountUnderlying = valueUSD * tokenMantissa * exchRateMantissa;

    // Apply exchange rate to convert from value in USD to  amount of underlying tokens
    amountUnderlying = amountUnderlying / exchRate / _qAdmin.MANTISSA_USD();
    
    if(asset.isYieldBearing){
      // If the asset is yield-bearing, we need one extra step to convert
      // from the amount of underlying tokens to the amount of yield-bearing
      // tokens
            
      // mTokenExchRate is value of 1 mToken in underlying tokens
      uint mTokenExchRate = _mTokenExchRateCurrent(address(token));

      // Multiply by mantissa first for maximum precision
      uint amountMToken = amountUnderlying * (10 ** 18) / mTokenExchRate;
      
      return amountMToken;
      
    }else{

      // The asset is already the native underlying token, so we can just
      // return the amount of underlying tokens directly
      return amountUnderlying;    
    }
  }

  /// @notice Convenience function for getting price feed from various oracles.
  /// Returned prices should ALWAYS be normalized to eight decimal places.
  /// @param underlyingToken Address of the underlying token
  /// @param oracleFeed Address of the oracle feed
  /// @return answer uint256, decimals uint8
  function _priceFeed(
                      IERC20 underlyingToken,
                      address oracleFeed
                      ) internal view returns(uint256, uint8) {

    if(oracleFeed == address(_DIAOracle)) {

      return _priceFeedDIA(underlyingToken);
      
    } else {

      return _priceFeedChainlink(oracleFeed);
      
    }
    
  }

  /// @notice Convenience function for getting price feed from DIA  oracle
  /// @param underlyingToken Address of the underlying token
  /// @return answer uint256, decimals uint8
  function _priceFeedDIA(IERC20 underlyingToken) internal view returns(uint256, uint8) {

    // We need to retrieve the `symbol` string from the token, which is not
    // a part of the standard IERC20 interface
    IERC20Metadata tokenWithSymbol = IERC20Metadata(address(underlyingToken));
      
    // DIA Oracle takes pair string input, e.g. `_DIAOracle.getValue("BTC/USD")`
    string memory key = string(abi.encodePacked(tokenWithSymbol.symbol(), "/USD"));

    // Catch and convert exceptions to the proper format
    if(keccak256(abi.encodePacked(key)) == keccak256(abi.encodePacked("WBTC/USD"))) {
      key = "BTC/USD";
    } else if(keccak256(abi.encodePacked(key)) == keccak256(abi.encodePacked("WETH/USD"))) {
      key = "ETH/USD";
    } else if(keccak256(abi.encodePacked(key)) == keccak256(abi.encodePacked("WMOVR/USD"))) {
      key = "MOVR/USD";
    } else if(keccak256(abi.encodePacked(key)) == keccak256(abi.encodePacked("WGLMR/USD"))) {
      key = "GLMR/USD";
    }
    
    // Get the value from DIA oracle
    (uint128 answer, uint128 timestamp) = _DIAOracle.getValue(key);

    // Ensure valid key is being used
    if (timestamp == 0) {
      revert CustomErrors.QPO_DIA_Key_Not_Found();
    }
    
    // By default, DIA oracles return the current asset price in USD with a
    // fix-comma notation of 8 decimal places.
    return (uint(answer), 8);
    
  }

  /// @notice Convenience function for getting price feed from Chainlink oracle
  /// @param oracleFeed Address of the chainlink oracle feed
  /// @return answer uint256, decimals uint8
  function _priceFeedChainlink(address oracleFeed) internal view returns(uint256, uint8) {
    AggregatorV3Interface aggregator = AggregatorV3Interface(oracleFeed);
    (, int256 answer,,,) =  aggregator.latestRoundData();
    uint8 decimals = aggregator.decimals();
    return (uint(answer), decimals);      
  }
    
  /// @notice Compound/Moonwell do not provide a view function for retrieving the
  /// current exchange rate between the yield bearing token and the underlying
  /// token. The protocol includes an exchangeRateCurrent() function which gives
  /// the value that we need, but it includes writes to storage, which is not gas
  /// efficient for our usage. Hence, we need this function to manually calculate
  /// the current exchange rate as a view function from the last stored exchange
  /// rate using 1) the interest accrual and 2) exchange rate formulas.
  /// @param mTokenAddress Address of the mToken contract
  function _mTokenExchRateCurrent(address mTokenAddress) internal view returns(uint){

    MTokenInterface mToken = MTokenInterface(mTokenAddress);
    
    // Step 1. Calculate Interest Accruals
    // See the accrueInterest() function in MToken.sol for implementation details
    
    // NOTE: Moonwell fork uses timestamps for interest calcs, NOT block as
    // per Compound. We will need to change the function call to
    // accrualBlockNumber() if we want to be compatible with Compound
    uint latestAccrualTimestamp = mToken.accrualBlockTimestamp();
    uint currentTimestamp = block.timestamp;
    if(currentTimestamp <= latestAccrualTimestamp){
      // No blocks have passed since the last interest accrual, so
      // we can just return the stored exchange rate directly
      return mToken.exchangeRateStored();
    }

    uint borrowRateMantissa = mToken.interestRateModel().getBorrowRate(mToken.getCash(),
                                                                       mToken.totalBorrows(),
                                                                       mToken.totalReserves()
                                                                       );
    uint simpleInterestFactor = borrowRateMantissa * (currentTimestamp - latestAccrualTimestamp);
    uint interestAccumulated = simpleInterestFactor * mToken.totalBorrows() / 1e18;
    uint totalBorrowsNew = interestAccumulated + mToken.totalBorrows();
    uint totalReservesNew = mToken.reserveFactorMantissa() * interestAccumulated / 1e18 + mToken.totalReserves();

    // Step 2. Calculate Exchange Rate
    // See exchangeRateCurrent(), exchangeRateStored(), and
    // exchangeRateStoredInternal()  in MToken.sol for implementation details
    uint totalSupply = mToken.totalSupply();
    uint cashPlusBorrowsMinusReserves = (mToken.getCash() + totalBorrowsNew - totalReservesNew);
    uint exchRateCurrent = cashPlusBorrowsMinusReserves * 1e18 / totalSupply;

    // Step 3. Perform sanity checks. `exchangeRateCurrent` should not deviate
    // by too much from `exchangeRateStored`
    if (exchRateCurrent > mToken.exchangeRateStored() * 11 / 10) {
      revert CustomErrors.QPO_ExchangeRateOutOfBound();
    }
    if (exchRateCurrent < mToken.exchangeRateStored() * 10 / 11) {
      revert CustomErrors.QPO_ExchangeRateOutOfBound();
    }

    return exchRateCurrent;
  }
}

