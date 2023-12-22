//SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.9 <=0.8.19;

import "./Initializable.sol";
import "./Math.sol";
import "./IERC20.sol";
import "./IFixedRateMarket.sol";
import "./IQodaLens.sol";
import "./IQollateralManager.sol";
import "./IQAdmin.sol";
import "./IQPriceOracle.sol";
import "./IQToken.sol";
import "./CustomErrors.sol";
import "./Interest.sol";
import "./QTypes.sol";
import "./QTypesPeripheral.sol";
import "./Utils.sol";

contract QodaLens is Initializable, IQodaLens {

  /// @notice Borrow side enum
  uint8 private constant _SIDE_BORROW = 0;

  /// @notice Lend side enum
  uint8 private constant _SIDE_LEND = 1;

  /// @notice PV enum
  uint8 private constant _TYPE_PV = 0;

  /// @notice FV enum
  uint8 private constant _TYPE_FV = 1;

  /// @notice Internal representation on null pointer for linked lists
  uint64 private constant _NULL_POINTER = 0;
    
  /// @notice Reserve storage gap so introduction of new parent class later on can be done via upgrade
  uint256[50] __gap;
  
  /// @notice Contract storing all global Qoda parameters
  IQAdmin private _qAdmin;

  /// @notice 0x0 null address for convenience
  address constant NULL = address(0);
  
  constructor() {
    _disableInitializers();
  }
  
  /// Note: Design decision: contracts are placed in constructor as Lens is
  /// stateless. Lens can be redeployed in case of contract upgrade
  function initialize(address qAdminAddress) public initializer {
    _qAdmin = IQAdmin(qAdminAddress);
  }
  
  /** VIEW FUNCTIONS **/

  /// @notice Gets the first N `Quote`s for a given `FixedRateMarket` and
  /// `side`, filtering for only if the quoter has the requisite hypothetical
  /// collateral ratio and allowance/balance for borrow and lend `Quote`s,
  /// respectively.
  /// For convenience, this function also returns the associated current
  /// collateral ratio and underlying balance of the publisher for the `Quote`.
  /// @param market Market to query
  /// @param side 0 for borrow `Quote`s, 1 for lend `Quote`s
  /// @param n Maximum number of `Quote`s to return
  /// @return QTypes.Quote[], uint[] `collateralRatio`s, uint[] underlying balances
  function takeNFilteredQuotes(
                               IFixedRateMarket market,
                               uint8 side,
                               uint n
                               ) external view returns(QTypes.Quote[] memory, uint[] memory, uint[] memory) {
    
    // Handle invalid `side` inputs
    if(side != _SIDE_BORROW && side != _SIDE_LEND) {
      revert CustomErrors.QL_InvalidSide();
    }
    
    // Get QollateralManager for getting collateral ratio
    IQollateralManager _qollateralManager = IQollateralManager(_qAdmin.qollateralManager());
    
    // Size of `Quote`s linkedlist may be smaller than requested
    n = Math.min(n, market.getNumQuotes(side));
    
    // Initialize empty arrays to return
    QTypes.Quote[] memory quotes = new QTypes.Quote[](n);
    uint[] memory collateralRatios = new uint[](n);
    uint[] memory underlyingBalances = new uint[](n);
    
    // Get the head of the linked list
    QTypes.Quote memory currQuote = market.getQuoteHead(side);
    
    uint i = 0;
    while(i < n && currQuote.id != _NULL_POINTER) {

      // Hack to avoid "stack too deep" error - get necessary values from
      // `_takeNFilteredQuotesHelper` function
      // values[0] => amountPV
      // values[1] => amountFV
      // values[2] => hypothetical collateral ratio
      // values[3] => protocol fee
      // values[4] => underlying token balance
      // values[5] => underlying token allowance
      uint[] memory values = _takeNFilteredQuotesHelper(market, currQuote);
      
      // Filter out borrow `Quote`s if user's hypothetical collateral ratio is
      // less than the `initCollateralRatio` parameter
      if(side == _SIDE_BORROW && values[2] < _qollateralManager.initCollateralRatio(currQuote.quoter)) {        
        currQuote = market.getQuote(side, currQuote.next);
        continue;
      }

      // Filter out lend `Quote`s if user's current allowance or balance is
      // less than the size they are lending (plus fees)
      if(side == _SIDE_LEND && (values[0] + values[3] > values[5] || values[0] + values[3] > values[4])) {        
        currQuote = market.getQuote(side, currQuote.next);
        continue;        
      }

      // Current `Quote` passes the filter checks. Add data to the arrays
      quotes[i] = currQuote;
      collateralRatios[i] = _qollateralManager.collateralRatio(currQuote.quoter);
      underlyingBalances[i] = values[4];
        
      // Update the counter
      unchecked { i++; }
      
      // Go to the next `Quote`
      currQuote = market.getQuote(side, currQuote.next);
    }
    
    // Correct actual length of dynamic array
    assembly {
      mstore(quotes, i)
      mstore(collateralRatios, i)
      mstore(underlyingBalances, i)
    }
    
    // Return the array
    return (quotes, collateralRatios, underlyingBalances);
  }
  
  /// @notice Gets the first N `Quote`s for a given `FixedRateMarket` and `side`.
  /// For convenience, this function also returns the associated current
  /// collateral ratio and underlying balance of the publisher for the `Quote`.
  /// @param market Market to query
  /// @param side 0 for borrow `Quote`s, 1 for lend `Quote`s
  /// @param n Maximum number of `Quote`s to return
  /// @return QTypes.Quote[], uint[] `collateralRatio`s, uint[] underlying balances
  function takeNQuotes(
                       IFixedRateMarket market,
                       uint8 side,
                       uint n
                       ) external view returns(QTypes.Quote[] memory, uint[] memory, uint[] memory){

    // Handle invalid `side` inputs
    if(side != _SIDE_BORROW && side != _SIDE_LEND) {
      revert CustomErrors.QL_InvalidSide();
    }

    // Size of `Quote`s linkedlist may be smaller than requested
    n = Math.min(n, market.getNumQuotes(side));

    // Initialize empty arrays to return
    QTypes.Quote[] memory quotes = new QTypes.Quote[](n);
    uint[] memory collateralRatios = new uint[](n);
    uint[] memory underlyingBalances = new uint[](n);

    // Get the head of the linked list
    QTypes.Quote memory currQuote = market.getQuoteHead(side);

    // Get QollateralManager for getting collateral ratio
    IQollateralManager _qollateralManager = IQollateralManager(_qAdmin.qollateralManager());
    
    // Populate the arrays using the linkedlist pointers
    for (uint i = 0; i < n;) {

      // Populate the `quotes` array
      quotes[i] = currQuote;
      address quoter = currQuote.quoter;

      // Populate the `collateralRatios` array
      uint collateralRatio = _qollateralManager.collateralRatio(quoter);
      collateralRatios[i] = collateralRatio;
      
      // Populate the `underlyingBalances` array
      uint balance = IERC20(market.underlyingToken()).balanceOf(quoter);
      underlyingBalances[i] = balance;

      // Go to next `Quote`
      currQuote = market.getQuote(side, currQuote.next);

      unchecked { i++; }
    }        
    
    return (quotes, collateralRatios, underlyingBalances);    
  }
  
  function _takeMarkets() internal view returns (address[] memory) {
    address[] memory assetAddresses = _qAdmin.allAssets();
    uint assetAddressesLength = assetAddresses.length;
    
    // Get # markets for market array initialization
    uint marketLength = 0;
    for (uint i = 0; i < assetAddressesLength;) {
      QTypes.Asset memory asset = _qAdmin.assets(IERC20(assetAddresses[i]));
      marketLength += asset.maturities.length;
      unchecked { i++; }
    }
    
    // Put unexpired markets into array, with length recorded in marketLength
    address[] memory marketAddresses = new address[](marketLength);
    marketLength = 0;
    for (uint i = 0; i < assetAddressesLength;) {
      IERC20 token = IERC20(assetAddresses[i]);
      QTypes.Asset memory asset = _qAdmin.assets(token);
      uint[] memory maturities = asset.maturities;
      uint maturitiesLength = maturities.length;
      for (uint j = 0; j < maturitiesLength;) {
        address marketAddress = _qAdmin.fixedRateMarkets(token, maturities[j]);
        if (block.timestamp < maturities[j] && _qAdmin.isMarketEnabled(marketAddress)) {
          marketAddresses[marketLength] = marketAddress;
          marketLength++;
        }
        unchecked { j++; }
      }
      unchecked { i++; }
    }
    
    // Correct actual length of dynamic array
    assembly {
      mstore(marketAddresses, marketLength)
    }
    
    return marketAddresses;
  }

  /// @notice Gets all open quotes from all unexpired market for a given account
  /// @param account Account for getting all open quotes
  /// @return QTypesPeripheral.AccountQuote[] Related quotes for given account
  function takeAccountQuotes(address account) external view returns (QTypesPeripheral.AccountQuote[] memory) {
    address[] memory marketAddresses = _takeMarkets();
    uint marketAddressesLength = marketAddresses.length;
    
    // Get # quotes for quote array initialization
    uint quoteLength = 0;
    for (uint i = 0; i < marketAddressesLength;) {
      IFixedRateMarket market = IFixedRateMarket(marketAddresses[i]);
      for (uint8 side = 0; side <= 1;) {
        quoteLength += market.getAccountQuotes(side, account).length;
        unchecked { side++; }
      }
      unchecked { i++; }
    }
    
    // Put quote into array, with length recorded in quoteLength
    QTypesPeripheral.AccountQuote[] memory quotes = new QTypesPeripheral.AccountQuote[](quoteLength);
    quoteLength = 0;
    for (uint i = 0; i < marketAddressesLength;) {
      IFixedRateMarket market = IFixedRateMarket(marketAddresses[i]);
      for (uint8 side = 0; side <= 1;) {
        uint64[] memory ids = market.getAccountQuotes(side, account);
        uint idsLength = ids.length;
        for (uint j = 0; j < idsLength;) {
          QTypes.Quote memory quote = market.getQuote(side, ids[j]);
          quotes[quoteLength] = QTypesPeripheral.AccountQuote({
            market: address(market),
            id: ids[j],
            side: side,
            quoter: quote.quoter,
            quoteType: quote.quoteType,
            APR: quote.APR,
            cashflow: quote.cashflow,
            filled: quote.filled
          });
          quoteLength++;
          unchecked { j++; }
        }
        unchecked { side++; }
      }
      unchecked { i++; }
    }
    
    return quotes;
  }

  /// @notice Convenience function to convert an array of `Quote` ids to
  /// an array of the underlying `Quote` structs
  /// @param market Market to query
  /// @param side 0 for borrow `Quote`s, 1 for lend `Quote`s
  /// @param quoteIds array of `Quote` ids to query
  /// @return QTypes.Quote[] Ordered array of `Quote`s corresponding to `Quote` ids
  function quoteIdsToQuotes(
                            IFixedRateMarket market,
                            uint8 side,
                            uint64[] calldata quoteIds
                            ) external view returns(QTypes.Quote[] memory){

    // Handle invalid `side` inputs
    if(side != _SIDE_BORROW && side != _SIDE_LEND) {
      revert CustomErrors.QL_InvalidSide();
    }

    // Initialize empty `Quote`s array to return
    uint quoteIdsLength = quoteIds.length;
    QTypes.Quote[] memory quotes = new QTypes.Quote[](quoteIdsLength);

    // Populate the array using the `quoteId` pointers
    for(uint i = 0; i < quoteIdsLength;) {
      quotes[i] = market.getQuote(side, quoteIds[i]);
      unchecked { i++; }
    }

    return quotes;
  }

  /// @notice Get the weighted average estimated APR for a requested market
  /// order `size`. The estimated APR is the weighted average of the first N
  /// `Quote`s APR until the full `size` is satisfied. The `size` can be in
  /// either PV terms or FV terms. This function also returns the confirmed
  /// filled amount in the case that the entire list of `Quote`s in the
  /// orderbook is smaller than the requested size. It returns default (0,0) if
  /// the orderbook is currently empty.
  /// @param market Market to query
  /// @param account Account to view estimated APR from
  /// @param size Size requested by the user. Can be in either PV or FV terms
  /// @param side 0 for borrow `Quote`s, 1 for lend `Quote`s
  /// @param quoteType 0 for PV, 1 for FV
  /// @return uint Estimated APR scaled by 1e4, uint Limit APR scaled by 1e4, uint Confirmed filled size
  function getEstimatedAPR(
                           IFixedRateMarket market,
                           address account,
                           uint size,
                           uint8 side,
                           uint8 quoteType
                           ) external view returns (uint, uint, uint) {

    // Handle invalid `side` inputs
    if(side != _SIDE_BORROW && side != _SIDE_LEND) {
      revert CustomErrors.QL_InvalidSide();
    }

    // Handle invalid `quoteType` inputs
    if(quoteType != _TYPE_PV && quoteType != _TYPE_FV) {
      revert CustomErrors.QL_InvalidQuoteType();
    }

    // Get the current top of book
    QTypes.Quote memory currQuote = market.getQuoteHead(side);

    // Store the remaining size to be filled
    uint remainingSize = size;

    // Store the estimated APR weighted-avg numerator calculation
    uint num = 0;
    
    // Store the estimated APR weighted-avg denominator calculation
    uint denom = 0;

    // Store the limit APR (min APR for lend and max APR for borrow)
    uint limitAPR = 0;
    
    // Loop until either the full size is satisfied or until the orderbook
    // runs out of quotes
    while(remainingSize != 0 && currQuote.id != _NULL_POINTER) {

      // Get quote to be iterated next
      QTypes.Quote memory nextQuote = market.getQuote(side, currQuote.next);

      // Ignore self `Quote`s in estimation calculations
      if(currQuote.quoter == account) {
        currQuote = nextQuote;
        continue;
      }
      
      // Get the size of the current `Quote` in the orderbook
      uint quoteSize = currQuote.cashflow;

      // Get maturity of market
      uint maturity = market.maturity();

      // Get mantissa for APR
      uint mantissa = _qAdmin.MANTISSA_BPS();

      // If the `quoteType` requested by user differs from the `quoteType`
      // of the current order, we need to do a FV -> PV conversion
      if(quoteType == _TYPE_PV && currQuote.quoteType == _TYPE_FV) {      
        quoteSize = Interest.FVToPV(
                                   currQuote.APR,
                                   currQuote.cashflow,
                                   block.timestamp,
                                   maturity,
                                   mantissa
                                   );
      }

      // If the `quoteType` requested by user differs from the `quoteType`
      // of the current order, we need to do a PV -> FV conversion
      if(quoteType == _TYPE_FV && currQuote.quoteType == _TYPE_PV) {
        quoteSize = Interest.PVToFV(
                                   currQuote.APR,
                                   currQuote.cashflow,
                                   block.timestamp,
                                   maturity,
                                   mantissa
                                   );        
      }
      
      uint currSize = Math.min(remainingSize, quoteSize);
      
      // Update the running estimated APR weighted-avg numerator calculation
      num += currSize * currQuote.APR;

      // Update the running estimated APR weighted-avg denominator calculation
      denom += currSize;

      // Update limit APR
      limitAPR = currQuote.APR;
      
      // Subtract the current `Quote` size from the remaining size to be filled
      remainingSize = remainingSize - currSize;

      // Move on to the next best `Quote`
      currQuote = nextQuote;
    }

    if(denom == 0) {

      // No orders in the orderbook, return default null values
      return (0,0,0);

    } else {

      // The `estimatedAPR` is the weighted avg of `Quote` APRs by `Quote`
      // sizes i.e., `num` divided by `denom`
      uint estimatedAPR = num / denom;
      
      return (estimatedAPR, limitAPR, size - remainingSize);
    }
  }
  
  /// @notice Get an account's maximum available collateral user can withdraw in specified asset.
  /// For example, what is the maximum amount of GLMR that an account can withdraw
  /// while ensuring their account health continues to be acceptable?
  /// Note: This function will return withdrawable amount that user has indeed collateralized, not amount that user can borrow
  /// Note: User can only withdraw up to `initCollateralRatio` for their own protection against instant liquidations
  /// @param account User account
  /// @param withdrawToken Currency of collateral to withdraw
  /// @return uint Maximum available collateral user can withdraw in specified asset
  function hypotheticalMaxWithdraw(
                                   address account,
                                   address withdrawToken
                                   ) external view returns (uint) {
    return _hypotheticalMaxWithdraw(account, withdrawToken);
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
  function hypotheticalMaxBorrowFV(
                                   address account,
                                   IFixedRateMarket borrowMarket
                                   ) external view returns (uint) {
    IQollateralManager _qollateralManager = IQollateralManager(_qAdmin.qollateralManager());
    return _qollateralManager.hypotheticalMaxBorrowFV(account, borrowMarket);
  }
  
  /// @notice Get an account's maximum value user can lend in specified market when protocol fee is factored in.
  /// @param account User account
  /// @param lendMarket Address of the `FixedRateMarket` market to lend
  /// @return uint Maximum value user can lend in specified market with protocol fee considered
  function hypotheticalMaxLendPV(
                                 address account,
                                 IFixedRateMarket lendMarket
                                 ) external view returns (uint) {
    IERC20 underlying_ = lendMarket.underlyingToken();
    uint balance = underlying_.balanceOf(account);
    return lendMarket.hypotheticalMaxLendPV(balance);
  }

  /// @notice Get an account's minimum collateral to further deposit if user wants to borrow specified amount in a certain market.
  /// For example, what is the minimum amount of USDC to deposit so that an account can borrow 100 DEV token from qDEVJUL22
  /// while ensuring their account health continues to be acceptable?
  /// @param account User account
  /// @param collateralToken Currency to collateralize in
  /// @param borrowMarket Address of the `FixedRateMarket` market to borrow
  /// @param borrowAmountFV Amount to borrow in local ccy
  /// @return uint Minimum collateral required to further deposit
  function minimumCollateralRequired(
                                     address account,
                                     IERC20 collateralToken,
                                     IFixedRateMarket borrowMarket,
                                     uint borrowAmountFV
                                     ) external view returns (uint) {
    IQollateralManager _qollateralManager = IQollateralManager(_qAdmin.qollateralManager());
    IQPriceOracle _qPriceOracle = IQPriceOracle(_qAdmin.qPriceOracle());
    uint initRatio = _qollateralManager.initCollateralRatio(account);
    uint virtualCollateralValue = _qollateralManager.virtualCollateralValue(account);
    uint virtualBorrowValue = _qollateralManager.hypotheticalVirtualBorrowValue(account, borrowMarket, borrowAmountFV, 0) + 1; // + 1 to avoid rounding problem
    uint virtualUSD = Utils.roundUpDiv(initRatio * virtualBorrowValue, _qAdmin.MANTISSA_COLLATERAL_RATIO()) - virtualCollateralValue;
    if (virtualUSD > _qAdmin.creditLimit(account)) {
      revert CustomErrors.QL_MaxBorrowExceeded();
    }
    uint realUSD = Utils.roundUpDiv(virtualUSD * _qAdmin.MANTISSA_FACTORS(), _qAdmin.collateralFactor(collateralToken));
    uint realLocal = _qPriceOracle.USDToLocal(collateralToken, realUSD) + 1; // + 1 to avoid rounding problem
    return realLocal;
  }
  
  function getAllMarketsByAsset(IERC20 token) public view returns (IFixedRateMarket[] memory) {
    QTypes.Asset memory asset = _qAdmin.assets(token);
    uint assetMaturitiesLength = asset.maturities.length;
    IFixedRateMarket[] memory fixedRateMarkets = new IFixedRateMarket[](assetMaturitiesLength);
    for (uint i = 0; i < assetMaturitiesLength;) {
      fixedRateMarkets[i] = IFixedRateMarket(_qAdmin.fixedRateMarkets(token, asset.maturities[i]));
      unchecked { i++; }
    }
    return fixedRateMarkets;
  }
    
  function totalLoansTradedByMarket(IFixedRateMarket market) public view returns (uint) {
    return totalUnredeemedLendsByMarket(market) + totalRedeemedLendsByMarket(market);
  }
    
  function totalRedeemedLendsByMarket(IFixedRateMarket market) public view returns (uint) {
    IQToken qToken = IQToken(market.qToken());
    return qToken.tokensRedeemedTotal();
  }
    
  function totalUnredeemedLendsByMarket(IFixedRateMarket market) public view returns (uint) {
    IQToken qToken = IQToken(market.qToken());
    return qToken.totalSupply();
  }
    
  function totalRepaidBorrowsByMarket(IFixedRateMarket market) public view returns (uint) {
    IERC20 token = market.underlyingToken();
    return token.balanceOf(address(market));
  }
    
  function totalUnrepaidBorrowsByMarket(IFixedRateMarket market) public view returns (uint) {
    return totalLoansTradedByMarket(market) - totalRepaidBorrowsByMarket(market); 
  }
    
  function totalLoansTradedByAsset(IERC20 token) public view returns (uint) {
    IFixedRateMarket[] memory fixedRateMarkets = getAllMarketsByAsset(token);
    uint fixedRateMarketsLength = fixedRateMarkets.length;
    uint totalLoansTraded = 0;
    for (uint i = 0; i < fixedRateMarketsLength;) {
      totalLoansTraded += totalLoansTradedByMarket(fixedRateMarkets[i]);
      unchecked { i++; }
    }
    return totalLoansTraded;
  }
    
  function totalRedeemedLendsByAsset(IERC20 token) public view returns (uint) {
    IFixedRateMarket[] memory fixedRateMarkets = getAllMarketsByAsset(token);
    uint fixedRateMarketsLength = fixedRateMarkets.length;
    uint totalRedeemedLends = 0;
    for (uint i = 0; i < fixedRateMarketsLength;) {
      totalRedeemedLends += totalRedeemedLendsByMarket(fixedRateMarkets[i]);
      unchecked { i++; }
    }
    return totalRedeemedLends;
  }
    
  function totalUnredeemedLendsByAsset(IERC20 token) public view returns (uint) {
    return totalLoansTradedByAsset(token) - totalRedeemedLendsByAsset(token);
  }
    
  function totalRepaidBorrowsByAsset(IERC20 token) public view returns (uint) {
    IFixedRateMarket[] memory fixedRateMarkets = getAllMarketsByAsset(token);
    uint fixedRateMarketsLength = fixedRateMarkets.length;
    uint totalRepaidBorrows = 0;
    for (uint i = 0; i < fixedRateMarketsLength;) {
      totalRepaidBorrows += totalRepaidBorrowsByMarket(fixedRateMarkets[i]);
      unchecked { i++; }
    }
    return totalRepaidBorrows;
  }
    
  function totalUnrepaidBorrowsByAsset(IERC20 token) public view returns (uint) {
    return totalLoansTradedByAsset(token) - totalRepaidBorrowsByAsset(token); 
  }
    
  function totalLoansTradedInUSD() public view returns (uint) {
    IQPriceOracle _qPriceOracle = IQPriceOracle(_qAdmin.qPriceOracle());
    address[] memory assets = _qAdmin.allAssets();
    uint assetsLength = assets.length;
    uint loansTradedUSD = 0;
    for (uint i = 0; i < assetsLength;) {
      IERC20 asset = IERC20(assets[i]);
      uint loansTradedByAsset = totalLoansTradedByAsset(asset);
      loansTradedUSD += _qPriceOracle.localToUSD(asset, loansTradedByAsset);
      unchecked { i++; }
    }
    return loansTradedUSD;
  }
  
  function totalRedeemedLendsInUSD() public view returns (uint) {
    IQPriceOracle _qPriceOracle = IQPriceOracle(_qAdmin.qPriceOracle());
    address[] memory assets = _qAdmin.allAssets();
    uint assetsLength = assets.length;
    uint redeemedLendsUSD = 0;
    for (uint i = 0; i < assetsLength;) {
      IERC20 asset = IERC20(assets[i]);
      uint redeemedLendsByAsset = totalRedeemedLendsByAsset(asset);
      redeemedLendsUSD += _qPriceOracle.localToUSD(asset, redeemedLendsByAsset);
      unchecked { i++; }
    }
    return redeemedLendsUSD;
  }
    
  function totalUnredeemedLendsInUSD() public view returns (uint) {
    return totalLoansTradedInUSD() - totalRedeemedLendsInUSD();
  }
    
  function totalRepaidBorrowsInUSD() public view returns (uint) {
    IQPriceOracle _qPriceOracle = IQPriceOracle(_qAdmin.qPriceOracle());
    address[] memory assets = _qAdmin.allAssets();
    uint assetsLength = assets.length;
    uint repaidBorrows = 0;
    for (uint i = 0; i < assetsLength;) {
      IERC20 asset = IERC20(assets[i]);
      uint repaidBorrowsByAsset = totalRepaidBorrowsByAsset(asset);
      repaidBorrows += _qPriceOracle.localToUSD(asset, repaidBorrowsByAsset);
      unchecked { i++; }
    }
    return repaidBorrows;
  }
    
  function totalUnrepaidBorrowsInUSD() public view returns (uint) {
    return totalLoansTradedInUSD() - totalRepaidBorrowsInUSD(); 
  }
  
  /// @notice Get the address of the `QollateralManager` contract
  /// @return address Address of `QollateralManager` contract
  function qollateralManager() external view returns(address){
    return _qAdmin.qollateralManager();
  }
  
  /// @notice Get the address of the `QAdmin` contract
  /// @return address Address of `QAdmin` contract
  function qAdmin() external view returns(address){
    return address(_qAdmin);
  }
  
  /// @notice Get the address of the `QPriceOracle` contract
  /// @return address Address of `QPriceOracle` contract
  function qPriceOracle() external view returns(address){
    return _qAdmin.qPriceOracle();
  }

  
  /** INTERNAL FUNCTIONS **/

  
  /// @notice Get an account's maximum available collateral user can withdraw in specified asset.
  /// For example, what is the maximum amount of GLMR that an account can withdraw
  /// while ensuring their account health continues to be acceptable?
  /// Note: This function will return withdrawable amount that user has indeed collateralized, not amount that user can borrow
  /// Note: User can only withdraw up to `initCollateralRatio` for their own protection against instant liquidations
  /// @param account User account
  /// @param withdrawToken Currency of collateral to withdraw
  /// @return uint Maximum available collateral user can withdraw in specified asset
  function _hypotheticalMaxWithdraw(
                                    address account,
                                    address withdrawToken
                                    ) internal view returns(uint) {
    IQollateralManager _qollateralManager = IQollateralManager(_qAdmin.qollateralManager());
    IQPriceOracle _qPriceOracle = IQPriceOracle(_qAdmin.qPriceOracle());
    IERC20 withdrawERC20 = IERC20(withdrawToken);
    QTypes.Asset memory asset = _qAdmin.assets(withdrawERC20);
    uint currentRatio = _qollateralManager.collateralRatio(account);
    uint minRatio = _qAdmin.initCollateralRatio(account);
    uint collateralBalance = _qollateralManager.collateralBalance(account, withdrawERC20);
    if (collateralBalance == 0 || currentRatio <= minRatio) {
      return 0;
    }
    if (currentRatio >= _qAdmin.UINT_MAX()) {
      return collateralBalance;
    }
    uint virtualBorrow = _qollateralManager.virtualBorrowValue(account);
    uint virtualUSD = virtualBorrow * (currentRatio - minRatio) / _qAdmin.MANTISSA_COLLATERAL_RATIO();
    uint realUSD = virtualUSD * _qAdmin.MANTISSA_FACTORS() / asset.collateralFactor;
    uint valueLocal = _qPriceOracle.USDToLocal(withdrawERC20, realUSD);
    return valueLocal <= collateralBalance ? valueLocal : collateralBalance;   
  }

  /// @notice This is a hacky helper function that helps to avoid the
  /// "stack too deep" compile error.
  /// @param market Market to query
  /// @param quote Quote to query
  /// @return uint[] [amountPV, amountFV, hcr, fee, balance, allowance]
  function _takeNFilteredQuotesHelper(
                                      IFixedRateMarket market,
                                      QTypes.Quote memory quote
                                      ) internal view returns(uint[] memory) {

    // Get the PV of the remaining amount in the `Quote`
    uint amountPV = market.getPV(
                                 quote.quoteType,
                                 quote.APR,
                                 quote.cashflow - quote.filled,
                                 block.timestamp,
                                 market.maturity()
                                 );                             

    // Get the FV of the remaining amount in the `Quote`
    uint amountFV = market.getFV(
                                 quote.quoteType,
                                 quote.APR,
                                 quote.cashflow - quote.filled,
                                 block.timestamp,
                                 market.maturity()
                                 );
    
    // Get QollateralManager for hypothetical collateral ratio
    IQollateralManager _qollateralManager = IQollateralManager(_qAdmin.qollateralManager());
    
    // Get the user's hypothetical collateral ratio after `Quote` fill
    uint hcr = _qollateralManager.hypotheticalCollateralRatio(
                                                              quote.quoter,
                                                              market.underlyingToken(),
                                                              0,
                                                              0,
                                                              market,
                                                              amountFV,
                                                              0
                                                              );
    
    // Get the fee and user's current balance and allowance
    uint fee = market.proratedProtocolFee(amountPV, block.timestamp);
    uint balance = IERC20(market.underlyingToken()).balanceOf(quote.quoter);
    uint allowance = IERC20(market.underlyingToken()).allowance(quote.quoter, address(market));

    uint[] memory values = new uint[](6);
    values[0] = amountPV;
    values[1] = amountFV;
    values[2] = hcr;
    values[3] = fee;
    values[4] = balance;
    values[5] = allowance;   

    return values;
  }

}

