// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.10;

import "./NoteKeeper.sol";

import "./SafeERC20.sol";

import "./IStaking.sol";
import "./ITreasury.sol";
import "./IERC20Metadata.sol";
import "./IBondDepository.sol";
import "./IPriceOracle.sol";

import "./IUniswapV2ERC20.sol";
import "./IUniswapV2Pair.sol";

/// @title Pana Bond Depository

contract PanaBondDepository is IBondDepository, NoteKeeper {
/* ======== DEPENDENCIES ======== */

  using SafeERC20 for IERC20;

/* ======== EVENTS ======== */

  event CreateMarket(uint256 indexed id, address indexed baseToken, address indexed quoteToken, uint256 initialPrice);
  event CloseMarket(uint256 indexed id);
  event Bond(uint256 indexed id, uint256 amount, uint256 price);
  event Tuned(uint256 indexed id, uint256 oldControlVariable, uint256 newControlVariable);

/* ======== STATE VARIABLES ======== */

  IPriceOracle public priceOracle;

  // Storage
  Market[] public markets; // persistent market data
  Terms[] public terms; // deposit construction data
  Metadata[] public metadata; // extraneous market data
  mapping(uint256 => Adjustment) public adjustments; // control variable changes

  // Queries
  mapping(address => uint256[]) public marketsForQuote; // market IDs for quote token

  bool public concurrentBondsPermitted;

/* ======== CONSTRUCTOR ======== */

  constructor(
    IPanaAuthority _authority,
    IERC20 _pana,
    IKarsha _karsha,
    IStaking _staking,
    ITreasury _treasury
  ) NoteKeeper(_authority, _pana, _karsha, _staking, _treasury) {
    // save gas for users by bulk approving stake() transactions
    _pana.approve(address(_staking), 1e45);
  }

  /**
   * @notice             sets price oracle for bond depository
   */
  function setPriceOracle(IPriceOracle _priceOracle) external onlyGovernor {
      priceOracle = _priceOracle;
  }

/* ======== DEPOSIT ======== */

  /**
   * @notice             deposit quote tokens in exchange for a bond from a specified market
   * @param _id          the ID of the market
   * @param _amount      the amount of quote token to spend
   * @param _maxPrice    the maximum price at which to buy
   * @param _user        the recipient of the payout
   * @param _referral    the front end operator address
   * @return payout_     the amount of KARSHA due
   * @return expiry_     the timestamp at which payout is redeemable
   * @return index_      the user index of the Note (used to redeem or query information)
   */
  function deposit(
    uint256 _id,
    uint256 _amount,
    uint256 _maxPrice,
    address _user,
    address _referral
  ) external override returns (
    uint256 payout_, 
    uint256 expiry_,
    uint256 index_
  ) {
    require(concurrentBondsPermitted || !hasNonMaturedNotes(_user), "Concurrent bonds are forbidden");

    Market storage market = markets[_id];
    Terms memory term = terms[_id];
    uint48 currentTime = uint48(block.timestamp);

    // Markets end at a defined timestamp
    // |-------------------------------------| t
    require(currentTime < term.conclusion, "Depository: market concluded");

    // Debt and the control variable decay over time
    _decay(_id, currentTime);

    // Users input a maximum price, which protects them from price changes after
    // entering the mempool. max price is a slippage mitigation measure
    { // add block scoping to avoid stack too deep
    uint256 price = _marketPrice(_id);

    require(price <= _maxPrice, "Depository: more than max price"); 

    /**
     * payout for the deposit = amount / price
     *
     * where
     * payout = PANA out
     * amount = quote tokens in
     * price = quote tokens : PANA 
     *
     * 1e36 = PANA decimals (18) + price decimals (18)
     */
    payout_ = (_amount * 1e36 / price) / (10 ** metadata[_id].quoteDecimals);

    // markets have a max payout amount, capping size because deposits
    // do not experience slippage. max payout is recalculated upon tuning
    require(payout_ <= market.maxPayout, "Depository: max size exceeded");
    
    /*
     * each market is initialized with a capacity
     *
     * this is either the number of PANA that the market can sell
     * (if capacity in quote is false), 
     *
     * or the number of quote tokens that the market can buy
     * (if capacity in quote is true)
     */
    market.capacity -= market.capacityInQuote
      ? _amount
      : payout_;

    /**
     * bonds mature with a cliff at a set timestamp
     * prior to the expiry timestamp, no payout tokens are accessible to the user
     * after the expiry timestamp, the entire payout can be redeemed
     *
     * there are two types of bonds: fixed-term and fixed-expiration
     *
     * fixed-term bonds mature in a set amount of time from deposit
     * i.e. term = 1 week. when alice deposits on day 1, her bond
     * expires on day 8. when bob deposits on day 2, his bond expires day 9.
     *
     * fixed-expiration bonds mature at a set timestamp
     * i.e. expiration = day 10. when alice deposits on day 1, her term
     * is 9 days. when bob deposits on day 2, his term is 8 days.
     */
    expiry_ = term.fixedTerm
      ? term.vesting + currentTime
      : term.vesting;

    // markets keep track of how many quote tokens have been
    // purchased, and how much PANA has been sold
    market.purchased += _amount;
    market.sold += uint256(payout_);

    // incrementing total debt raises the price of the next bond
    market.totalDebt += uint256(payout_);

    emit Bond(_id, _amount, price);
    }

    // send quote token to treasury, mint PANA, and stake the payout
    _sendToTreasury(_id, _amount, payout_, _referral);

    /**
     * user data is stored as Notes. these are isolated array entries
     * storing the amount due, the time created, the time when payout
     * is redeemable, the time when payout was redeemed, and the ID
     * of the market deposited into
     */
    index_ = addNote(
      _user,
      payout_,
      uint48(expiry_),
      uint48(_id)
    );

    // if max debt is breached, the market is closed 
    // this a circuit breaker
    if (term.maxDebt < market.totalDebt) {
        market.capacity = 0;
        emit CloseMarket(_id);
    } else {
      // if market will continue, the control variable is tuned to hit targets on time
      _tune(_id, currentTime);
    }
  }

  /**
    * @notice             sends funds to treasury and mints correct amount of PANA for payout
    * @param _id          the ID of the market
    * @param _amount      the amount of quote token being sent
    * @param _payout      the amount of PANA to be paid to depositor
    */
  function _sendToTreasury(uint256 _id, uint256 _amount, uint256 _payout, address _referral) internal {
      /**
        * payment is transferred to the treasury and PANA is minted for 
        * the user payout. if the quoteToken is a reserve asset or LP
        * token, then it should be deposited to the treasury. if not,
        * it should be transferred.
        */
      Market memory market = markets[_id];
      
      uint256 toTreasury = 0;
      uint256 toRef = 0;
          
      if (market.quoteTokenIsReserve) {
          // transfer payment from user to this contract
          market.quoteToken.safeTransferFrom(msg.sender, address(this), _amount);

          // get rewards for Treasury and referral
          (toRef, toTreasury) = giveRewards(_payout, _referral);
          
          // calculate amount to mint
          uint256 toMint = _payout + toRef + toTreasury;

          // deposit the payment to the treasury
          treasury.deposit(_amount, address(market.quoteToken), toMint);
      } else {
          // transfer payment from user to treasury directly
          market.quoteToken.safeTransferFrom(msg.sender, address(treasury), _amount);
          
          // get rewards for DAO, Treasury and referral
          (toRef, toTreasury) = giveRewards(_payout, _referral);

          // mint PANA for payout and reward
          treasury.mint(address(this), _payout + toRef + toTreasury);
      }

      if (toTreasury > 0) {
        // Rewards generated for Treasury should be sent to Treasury immediately
        sendRewardsToTreasury(toTreasury);
      }

      // stake the payout while vesting
      staking.stake(address(this), _payout);
  }


  /**
   * @notice             decay debt, and adjust control variable if there is an active change
   * @param _id          ID of market
   * @param _time        uint48 timestamp (saves gas when passed in)
   */
  function _decay(uint256 _id, uint48 _time) internal {

    // Debt decay

    /*
     * Debt is a time-decayed sum of tokens spent in a market
     * Debt is added when deposits occur and removed over time
     * |
     * |    debt falls with
     * |   / \  inactivity       / \
     * | /     \              /\/    \
     * |         \           /         \
     * |           \      /\/            \
     * |             \  /  and rises       \
     * |                with deposits
     * |
     * |------------------------------------| t
     */
    markets[_id].totalDebt -= debtDecay(_id);
    metadata[_id].lastDecay = _time;


    // Control variable decay

    // The bond control variable is continually tuned. When it is lowered (which
    // lowers the market price), the change is carried out smoothly over time.
    if (adjustments[_id].active) {
      Adjustment storage adjustment = adjustments[_id];

      (uint256 adjustBy, uint48 secondsSince, bool stillActive) = _controlDecay(_id);
      terms[_id].controlVariable -= adjustBy;

      if (stillActive) {
        adjustment.change -= adjustBy;
        adjustment.timeToAdjusted -= secondsSince;
        adjustment.lastAdjustment = _time;
      } else {
        adjustment.active = false;
      }
    }
  }

  /**
   * @notice             auto-adjust control variable to hit capacity/spend target
   * @param _id          ID of market
   * @param _time        uint48 timestamp (saves gas when passed in)
   */
  function _tune(uint256 _id, uint48 _time) internal {
    Metadata memory meta = metadata[_id];

    if (_time >= meta.lastTune + meta.tuneInterval) {
      Market memory market = markets[_id];
      
      // compute seconds remaining until market will conclude
      uint256 timeRemaining = terms[_id].conclusion - _time;
      uint256 price = _marketPrice(_id);

      // standardize capacity into an base token amount
      // PANA decimals (18) + price decimals (18)
      uint256 capacity = market.capacityInQuote
        ? (market.capacity * 1e36 / price) / (10 ** meta.quoteDecimals)
        : market.capacity;

      /**
       * calculate the correct payout to complete on time assuming each bond
       * will be max size in the desired deposit interval for the remaining time
       *
       * i.e. market has 10 days remaining. deposit interval is 1 day. capacity
       * is 10,000 PANA. max payout would be 1,000 PANA (10,000 * 1 / 10).
       */  
      markets[_id].maxPayout = uint256(capacity * meta.depositInterval / timeRemaining);

      // calculate the ideal total debt to satisfy capacity in the remaining time
      uint256 targetDebt = capacity * meta.length / timeRemaining;

      // derive a new control variable from the target debt and current supply
      uint256 newControlVariable = uint256(price * treasury.baseSupply() / targetDebt);

      emit Tuned(_id, terms[_id].controlVariable, newControlVariable);

      if (newControlVariable >= terms[_id].controlVariable) {
        terms[_id].controlVariable = newControlVariable;
      } else {
        // if decrease, control variable change will be carried out over the tune interval
        // this is because price will be lowered
        uint256 change = terms[_id].controlVariable - newControlVariable;
        adjustments[_id] = Adjustment(change, _time, meta.tuneInterval, true);
      }
      metadata[_id].lastTune = _time;
    }
  }

/* ======== CREATE ======== */

  /**
   * @notice             creates a new market type
   * @dev                current price should be in 18 decimals.
   * @param _quoteToken  token used to deposit
   * @param _market      [capacity (in PANA or quote), initial price / PANA (18 decimals), debt buffer (3 decimals)]
   * @param _booleans    [capacity in quote, quote is reserve, quote is LP, fixed term]
   * @param _terms       [vesting length (if fixed term) or vested timestamp, conclusion timestamp]
   * @param _intervals   [deposit interval (seconds), tune interval (seconds)]
   * @return id_         ID of new bond market
   */
  function create(
    IERC20 _quoteToken,
    uint256[3] memory _market,
    bool[4] memory _booleans,
    uint256[2] memory _terms,
    uint32[2] memory _intervals
  ) external override onlyPolicy returns (uint256 id_) {

    // the length of the program, in seconds
    uint256 secondsToConclusion = _terms[1] - block.timestamp;

    // the decimal count of the quote token
    uint256 decimals = IERC20Metadata(address(_quoteToken)).decimals();

    /* 
     * initial target debt is equal to capacity (this is the amount of debt
     * that will decay over in the length of the program if price remains the same).
     * it is converted into base token terms if passed in in quote token terms.
     *
     * 1e36 = PANA decimals (18) + initial price decimals (18)
     */
    uint256 targetDebt = uint256(_booleans[0] ?
    (_market[0] * 1e36 / _market[1]) / 10 ** decimals 
    : _market[0]
    );

    /*
     * max payout is the amount of capacity that should be utilized in a deposit
     * interval. for example, if capacity is 1,000 PANA, there are 10 days to conclusion, 
     * and the preferred deposit interval is 1 day, max payout would be 100 PANA.
     */
    uint256 maxPayout = uint256(targetDebt * _intervals[0] / secondsToConclusion);

    /*
     * max debt serves as a circuit breaker for the market. let's say the quote
     * token is a stablecoin, and that stablecoin depegs. without max debt, the
     * market would continue to buy until it runs out of capacity. this is
     * configurable with a 3 decimal buffer (1000 = 1% above initial price).
     * note that its likely advisable to keep this buffer wide.
     * note that the buffer is above 100%. i.e. 10% buffer = initial debt * 1.1
     */
    uint256 maxDebt = targetDebt + (targetDebt * _market[2] / 1e5); // 1e5 = 100,000. 10,000 / 100,000 = 10%.

    /*
     * the control variable is set so that initial price equals the desired
     * initial price. the control variable is the ultimate determinant of price,
     * so we compute this last.
     *
     * price = control variable * debt ratio
     * debt ratio = total debt / supply
     * therefore, control variable = price / debt ratio
     */
    uint256 controlVariable = _market[1] * treasury.baseSupply() / targetDebt;

    // depositing into, or getting info for, the created market uses this ID
    id_ = markets.length;

    markets.push(Market({
      quoteToken: _quoteToken, 
      quoteTokenIsReserve: _booleans[1],
      capacityInQuote: _booleans[0],
      capacity: _market[0],
      totalDebt: targetDebt, 
      maxPayout: maxPayout,
      purchased: 0,
      sold: 0
    }));

    terms.push(Terms({
      fixedTerm: _booleans[3], 
      controlVariable: uint256(controlVariable),
      vesting: uint48(_terms[0]), 
      conclusion: uint48(_terms[1]), 
      maxDebt: uint256(maxDebt) 
    }));

    metadata.push(Metadata({
      lastTune: uint48(block.timestamp),
      lastDecay: uint48(block.timestamp),
      length: uint48(secondsToConclusion),
      depositInterval: _intervals[0],
      tuneInterval: _intervals[1],
      quoteDecimals: uint8(decimals),
      quoteIsLPToken: _booleans[2]
    }));

    marketsForQuote[address(_quoteToken)].push(id_);

    // Approve the treasury for quoteToken if quoteTokenIsReserve
    if (_booleans[1]) _quoteToken.approve(address(treasury), type(uint256).max);

    emit CreateMarket(id_, address(pana), address(_quoteToken), _market[1]);
  }

  /**
   * @notice             disable existing market
   * @param _id          ID of market to close
   */
  function close(uint256 _id) external override onlyPolicy {
    terms[_id].conclusion = uint48(block.timestamp);
    markets[_id].capacity = 0;
    emit CloseMarket(_id);
  }

  function permitConcurrentBonds(bool permit) external onlyPolicy {
    concurrentBondsPermitted = permit;
  }

  /**
   * @notice             gets token price in quote tokens from oracle
   * @param _id          ID of market
   * @return             oracle price for market in PANA decimals
   */
  function _getOraclePrice(uint256 _id) internal returns (uint256) {
    Market memory market = markets[_id];
    Metadata memory meta = metadata[_id];

    if (meta.quoteIsLPToken) {
      /**
       * to find a price of 1 LP token, we need:
       * - call oracle to get the price of other token in Pana
       * - calculate LP total reserves in Pana
       * - divide LP total supply by total reserves 
       */

      IUniswapV2Pair pair = IUniswapV2Pair(address(market.quoteToken));

      address token = pair.token0();
      address token1 = pair.token1();
      (uint256 reserve0, uint256 reserve1, ) = pair.getReserves();
      
      if (token == address(pana) || token == address(karsha)) {
        (token, token1) = (token1, token);
        (reserve0, reserve1) = (reserve1, reserve0);
      }
      else {
        require(token1 == address(pana) || token1 == address(karsha), "Invalid pair");
      }

      uint256 tokenDecimals = IERC20Metadata(token).decimals();

      // tokenPrice is in PANA decimals
      uint256 tokenPrice = priceOracle.consult(token, 10 ** tokenDecimals, token1);

      // total reserves calculated in Pana/Karsha
      uint256 totalReserves = reserve1 + reserve0 * tokenPrice / (10 ** tokenDecimals);

      // price of 1 pana/Karsha in LP token
      uint256 oraclePrice = pair.totalSupply() * 1e18 / totalReserves;

      if (token1 == address(karsha)) {
        // adjust karsha price to pana per current index
        oraclePrice = oraclePrice / staking.index();
      }

      return oraclePrice;
    }
    else {
      uint256 quoteDecimals = IERC20Metadata(address(market.quoteToken)).decimals();

      // TWAP oracle returns price in terms of tokenOut but we need it in PANA decimals
      uint256 decimals = IERC20Metadata(address(pana)).decimals();
      if (decimals > quoteDecimals) {
        decimals += decimals - quoteDecimals;
      }
      else {
        decimals -= quoteDecimals - decimals;
      }

      return priceOracle.consult(address(pana), 10 ** decimals, address(market.quoteToken));
    }
  }

  /**
   * @notice                  calculate current market price of quote token in base token
   * @dev                     see marketPrice() for explanation of price computation
   * @dev                     uses info from storage because data has been updated before call (vs marketPrice())
   * @param _id               market ID
   * @return                  price for market in PANA decimals
   */ 
  function _marketPrice(uint256 _id) internal returns (uint256) {
    uint256 price =  terms[_id].controlVariable 
      * _debtRatio(_id) 
      / (10 ** metadata[_id].quoteDecimals);

    // check oracle price and select minimum
    if (address(priceOracle) != address(0)) {
      uint256 oraclePrice = _getOraclePrice(_id);
      if (oraclePrice < price) {
        price = oraclePrice;
      }
    }

    return price;  
  }


/* ======== EXTERNAL VIEW ======== */

  /**
   * @notice             calculate current ratio of debt to supply
   * @dev                uses current debt, which accounts for debt decay since last deposit (vs _debtRatio())
   * @param _id          ID of market
   * @return             debt ratio for market in quote decimals
   */
  function debtRatio(uint256 _id) public view override returns (uint256) {
    return 
      currentDebt(_id)
      * (10 ** metadata[_id].quoteDecimals)
      / treasury.baseSupply(); 
  }

  /**
   * @notice             calculate debt factoring in decay
   * @dev                accounts for debt decay since last deposit
   * @param _id          ID of market
   * @return             current debt for market in PANA decimals
   */
  function currentDebt(uint256 _id) public view override returns (uint256) {
    return markets[_id].totalDebt - debtDecay(_id);
  }

  /**
   * @notice             amount of debt to decay from total debt for market ID
   * @param _id          ID of market
   * @return             amount of debt to decay
   */
  function debtDecay(uint256 _id) public view override returns (uint256) {
    Metadata memory meta = metadata[_id];

    uint256 secondsSince = block.timestamp - meta.lastDecay;

    return uint256(markets[_id].totalDebt * secondsSince / meta.length);
  }

  /**
   * @notice             up to date control variable
   * @dev                accounts for control variable adjustment
   * @param _id          ID of market
   * @return             control variable for market in PANA decimals
   */
  function currentControlVariable(uint256 _id) public view returns (uint256) {
    (uint256 decay,,) = _controlDecay(_id);
    return terms[_id].controlVariable - decay;
  }

  /**
   * @notice             is a given market accepting deposits
   * @param _id          ID of market
   */
  function isLive(uint256 _id) public view override returns (bool) {
    return (markets[_id].capacity != 0 && terms[_id].conclusion > block.timestamp);
  }

  /**
   * @notice returns an array of all active market IDs
   */
  function liveMarkets() external view override returns (uint256[] memory) {
    uint256 num;
    for (uint256 i = 0; i < markets.length; i++) {
      if (isLive(i)) num++;
    }

    uint256[] memory ids = new uint256[](num);
    uint256 nonce;
    for (uint256 i = 0; i < markets.length; i++) {
      if (isLive(i)) {
        ids[nonce] = i;
        nonce++;
      }
    }
    return ids;
  }

  /**
   * @notice             returns an array of all active market IDs for a given quote token
   * @param _token       quote token to check for
   */
  function liveMarketsFor(address _token) external view override returns (uint256[] memory) {
    uint256[] memory mkts = marketsForQuote[_token];
    uint256 num;

    for (uint256 i = 0; i < mkts.length; i++) {
      if (isLive(mkts[i])) num++;
    }

    uint256[] memory ids = new uint256[](num);
    uint256 nonce;

    for (uint256 i = 0; i < mkts.length; i++) {
      if (isLive(mkts[i])) {
        ids[nonce] = mkts[i];
        nonce++;
      }
    }
    return ids;
  }

  /**
   * @notice             View Only - gets token price in quote tokens from oracle
   * @param _id          ID of market
   * @return             oracle price for market in PANA decimals
   */
  function getOraclePriceView(uint256 _id) public view returns (uint256) {
    Market memory market = markets[_id];
    Metadata memory meta = metadata[_id];

    if (meta.quoteIsLPToken) {
      /**
       * to find a price of 1 LP token, we need:
       * - call oracle to get the price of other token in Pana
       * - calculate LP total reserves in Pana
       * - divide LP total supply by total reserves 
       */

      IUniswapV2Pair pair = IUniswapV2Pair(address(market.quoteToken));

      address token = pair.token0();
      address token1 = pair.token1();
      (uint256 reserve0, uint256 reserve1, ) = pair.getReserves();
      
      if (token == address(pana) || token == address(karsha)) {
        (token, token1) = (token1, token);
        (reserve0, reserve1) = (reserve1, reserve0);
      }
      else {
        require(token1 == address(pana) || token1 == address(karsha), "Invalid pair");
      }

      uint256 tokenDecimals = IERC20Metadata(token).decimals();

      // tokenPrice is in PANA decimals
      uint256 tokenPrice = priceOracle.consultReadonly(token, 10 ** tokenDecimals, token1);

      // total reserves calculated in Pana/Karsha
      uint256 totalReserves = reserve1 + reserve0 * tokenPrice / (10 ** tokenDecimals);

      // price of 1 pana/Karsha in LP token
      uint256 oraclePrice = pair.totalSupply() * 1e18 / totalReserves;

      if (token1 == address(karsha)) {
        // adjust karsha price to pana per current index
        oraclePrice = oraclePrice / staking.index();
      }

      return oraclePrice;
    }
    else {
      uint256 quoteDecimals = IERC20Metadata(address(market.quoteToken)).decimals();

      // TWAP oracle returns price in terms of tokenOut but we need it in PANA decimals
      uint256 decimals = IERC20Metadata(address(pana)).decimals();
      if (decimals > quoteDecimals) {
        decimals += decimals - quoteDecimals;
      }
      else {
        decimals -= quoteDecimals - decimals;
      }

      return priceOracle.consultReadonly(address(pana), 10 ** decimals, address(market.quoteToken));
    }
  }

  /**
   * @notice                  View Only Function - calculate current market price of quote token in base token
   * @param _id               market ID
   * @return                  price for market in PANA decimals
   */ 
  function marketPrice(uint256 _id) external view returns (uint256) {
    uint256 price =  currentControlVariable(_id) 
      * debtRatio(_id) 
      / (10 ** metadata[_id].quoteDecimals);

    // check oracle price and select minimum
    if (address(priceOracle) != address(0)) {
      uint256 oraclePrice = getOraclePriceView(_id);
      if (oraclePrice < price) {
        price = oraclePrice;
      }
    }

    return price;  
  }

  /* ======== INTERNAL VIEW ======== */

  /**
   * @notice                  calculate debt factoring in decay
   * @dev                     uses info from storage because data has been updated before call (vs debtRatio())
   * @param _id               market ID
   * @return                  current debt for market in quote decimals
   */ 
  function _debtRatio(uint256 _id) internal view returns (uint256) {
    return 
      markets[_id].totalDebt
      * (10 ** metadata[_id].quoteDecimals)
      / treasury.baseSupply(); 
  }

  /**
   * @notice                  amount to decay control variable by
   * @param _id               ID of market
   * @return decay_           change in control variable
   * @return secondsSince_    seconds since last change in control variable
   * @return active_          whether or not change remains active
   */ 
  function _controlDecay(uint256 _id) internal view returns (uint256 decay_, uint48 secondsSince_, bool active_) {
    Adjustment memory info = adjustments[_id];
    if (!info.active) return (0, 0, false);

    secondsSince_ = uint48(block.timestamp) - info.lastAdjustment;

    active_ = secondsSince_ < info.timeToAdjusted;
    decay_ = active_ 
      ? info.change * secondsSince_ / info.timeToAdjusted
      : info.change;
  }
}
