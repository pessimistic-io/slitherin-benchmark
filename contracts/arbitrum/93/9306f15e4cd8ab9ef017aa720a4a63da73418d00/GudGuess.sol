/**
 * Gud Guess (GG)
 * https://gudguess.com
 * https://t.me/gudguess
 * https://twitter.com/gudguess
 **/

// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

import "./FixedPoint96.sol";
import "./HolderRewards.sol";
import "./UniswapV3FeeERC20.sol";
import "./IGudGuessTickets.sol";
import "./ITwapUtils.sol";
import "./IWinnersCircle.sol";
import "./BokkyPooBahsDateTimeLibrary.sol";

contract GudGuess is UniswapV3FeeERC20 {
  uint32 constant DENOMENATOR = 10000;

  ITwapUtils public twapUtils;
  HolderRewards public rewards;
  IGudGuessTickets public tickets;
  IWinnersCircle public winnersCircle;

  address public priceToken;
  IUniswapV3Pool public pricePool;
  IUniswapV3Pool public nativeStablePool;
  bool _isPoolPairedWETH9;

  address public adminWallet;

  // percentage of ticket sales that are burned
  uint32 public burnPerc = (DENOMENATOR * 25) / 100; // 25%
  // percentage of total pool to use for weekly winnings
  // will roll over if no winnings for the week
  uint32 public winningsPerc = (DENOMENATOR * 40) / 100; // 40%
  // percentage of jackpot that will pay out in rewards to holders each week
  uint32 public rewardsPerc = (DENOMENATOR * 1) / 100; // 1%
  // percentage of winnings per weekly close used to compensate for R&D
  uint32 public adminPerc = (DENOMENATOR * 5) / 100; // 5%

  // price per ticket changes dynamically & linearly on a sliding scale.
  // the earlier in the week you buy tickets the closer to the min
  // your tickets will be up to the max the closer to the close date
  uint256 public pricePerTicketMinUSDX96 = 2 * FixedPoint96.Q96; // $2 per ticket;
  uint256 public pricePerTicketMaxUSDX96 = 5 * FixedPoint96.Q96; // $5 per ticket ;

  // in addition to increasing price per ticket closer to the deadline,
  // we will also reduce the guesser's share of the jackpot as the close approaches
  uint32 public minGuessJackpotWeight = 6 * DENOMENATOR;
  uint32 public maxGuessJackpotWeight = 9 * DENOMENATOR;

  uint256 public launchTime;

  uint256 public swapAtAmountSupplyPerc = (DENOMENATOR * 2) / 1000; // 0.2%
  bool public swapEnabled = true;
  bool public taxEnabled = true;

  // precisionDecimals is the number of decimals compared to 10**18 that determines
  // the precision we are evaluating and storing weekly close prices at.
  // For example, 18 means we are storing both guesses and weekly close
  // values at $1 precision compared to the USD value, (10**18 decimals)
  // 16 would be precise to the $0.01
  uint8 public precisionDecimals = 16;
  uint256 public guessCutoffBeforeClose = 3 days;
  // weeklyClose => price
  mapping(uint256 => uint256) public weeklyClosePrice;
  // weeklyClose => total tickets sold
  mapping(uint256 => uint256) public totalWeeklyGuesses;
  // weeklyClose => priceGuess => total tickets sold at this price
  mapping(uint256 => mapping(uint256 => uint256)) public weeklyGuesses;
  // weeklyClose => priceGuess => total weight across all guessors
  mapping(uint256 => mapping(uint256 => uint256)) public weeklyWeights;

  mapping(address => bool) public amms; // AMM == Automated Market Maker
  mapping(address => bool) public isBot;
  mapping(address => bool) public rewardsExcluded;

  bool _swapping;
  modifier lockSwap() {
    _swapping = true;
    _;
    _swapping = false;
  }

  event Burn(address indexed wallet, uint256 amount);
  event BuyTicket(
    address indexed wallet,
    uint256 indexed weeklyClose,
    uint256 priceX96
  );
  event SubmitWeeklyClose(
    uint256 indexed weeklyClose,
    uint256 closePriceX96,
    uint256 totalGuesses,
    uint256 totalWinners,
    uint256 totalWeight
  );

  constructor(
    INonfungiblePositionManager _manager,
    ISwapRouter _swapRouter,
    address _priceToken,
    IUniswapV3Pool _pricePool,
    IUniswapV3Pool _nativeStablePool,
    bool __isPoolPairedWETH9,
    address _factory,
    address _WETH9
  )
    UniswapV3FeeERC20(
      'Gud Guess',
      'GG',
      _manager,
      _swapRouter,
      _factory,
      _WETH9
    )
  {
    rewards = new HolderRewards(address(this));

    adminWallet = msg.sender;
    rewardsExcluded[address(this)] = true;

    priceToken = _priceToken;
    pricePool = _pricePool;
    nativeStablePool = _nativeStablePool;
    _isPoolPairedWETH9 = __isPoolPairedWETH9;

    uint256 _supply = 100_000_000 * 10 ** decimals();
    _mint(address(this), _supply);
  }

  function _transfer(
    address sender,
    address recipient,
    uint256 amount
  ) internal virtual override {
    bool _isBuy = amms[sender] && recipient != address(swapRouter);
    bool _isSell = amms[recipient];

    if (_isBuy || _isSell) {
      require(launchTime > 0, 'TRANSFER: not launched');
    }

    uint256 _tax;
    if (launchTime > 0) {
      if (_isBuy) {
        if (block.timestamp <= launchTime + 10 seconds) {
          isBot[recipient] = true;
        } else if (block.timestamp <= launchTime + 30 minutes) {
          uint256 _launchMax = balanceOf(recipient) + amount;
          require(_launchMax <= totalSupply() / 100, 'max 1% at launch');
        }

        if (taxEnabled) {
          // first 30 days tax at 5%, afterwards 1%
          _tax = block.timestamp < launchTime + 30 days
            ? (amount * 5) / 100
            : (amount * 1) / 100;
          super._transfer(sender, address(this), _tax);
          _afterTokenTransfer(sender, address(this), _tax);
        }
      } else {
        require(!isBot[recipient], 'TRANSFER: bot0');
        require(!isBot[sender], 'TRANSFER: bot1');
        require(!isBot[_msgSender()], 'TRANSFER: bot2');
      }

      if (
        !_swapping &&
        swapEnabled &&
        liquidityPosInitialized &&
        balanceOf(address(this)) >= _getSwapAtAmount()
      ) {
        _swapForETHAndProcess();
      }
      _checkAndSubmitPreviousWeeklyClose();
    }

    super._transfer(sender, recipient, amount - _tax);
    _afterTokenTransfer(sender, recipient, amount - _tax);
  }

  // NOTE: need this to execute _afterTokenTransfer callback (not present in openzeppelin 3.4.2)
  function _mint(address account, uint256 amount) internal override {
    super._mint(account, amount);
    _afterTokenTransfer(address(0), account, amount);
  }

  // NOTE: need this to execute _afterTokenTransfer callback (not present in openzeppelin 3.4.2)
  function _burn(address account, uint256 amount) internal override {
    super._burn(account, amount);
    _afterTokenTransfer(account, address(0), amount);
  }

  function _swapForETHAndProcess() internal lockSwap {
    uint256 _swapAmount = _getSwapAtAmount();
    uint256 _burnTokens = (_swapAmount * burnPerc) / DENOMENATOR;
    _burn(address(this), _burnTokens);
    _swapTokensForETH(_swapAmount - _burnTokens);
  }

  function _buyTicket(address _user, uint256 _priceUSDX96) internal {
    uint256 _nextWeeklyClose = getWeeklyCloseFromTimestamp(block.timestamp);
    uint256 _weeklyCloseForGuess = block.timestamp <
      _nextWeeklyClose - guessCutoffBeforeClose
      ? _nextWeeklyClose
      : getWeeklyCloseFromTimestamp(block.timestamp + 7 days);

    uint256 _rawPriceAtPrecision = (_priceUSDX96 * 10 ** 18) /
      FixedPoint96.Q96 /
      10 ** precisionDecimals;
    uint256 _finalPriceUSDX96 = (_rawPriceAtPrecision *
      FixedPoint96.Q96 *
      10 ** precisionDecimals) / 10 ** 18;
    uint32 _weight = _getCurrentWinningsWeight();

    tickets.mint(
      _user,
      _weeklyCloseForGuess,
      priceToken,
      address(pricePool),
      address(nativeStablePool),
      _finalPriceUSDX96,
      _weight
    );
    totalWeeklyGuesses[_weeklyCloseForGuess]++;
    weeklyGuesses[_weeklyCloseForGuess][_finalPriceUSDX96]++;
    weeklyWeights[_weeklyCloseForGuess][_finalPriceUSDX96] += _weight;
    emit BuyTicket(_user, _weeklyCloseForGuess, _finalPriceUSDX96);
  }

  function _checkAndSubmitPreviousWeeklyClose() internal {
    uint256 _prevWeeklyClose = getWeeklyCloseFromTimestamp(
      block.timestamp - 7 days
    );
    if (
      totalWeeklyGuesses[_prevWeeklyClose] == 0 ||
      weeklyClosePrice[_prevWeeklyClose] > 0
    ) {
      return;
    }
    uint256 _jackpotETH = getTotalJackpotBalance();
    uint256 _fullClosePriceX96 = getPriceTokenPriceUSDX96();
    uint256 _rawClosePriceAtPrecision = (_fullClosePriceX96 * 10 ** 18) /
      FixedPoint96.Q96 /
      10 ** precisionDecimals;
    uint256 _finalClosePriceX96 = (_rawClosePriceAtPrecision *
      FixedPoint96.Q96 *
      10 ** precisionDecimals) / 10 ** 18;
    weeklyClosePrice[_prevWeeklyClose] = _finalClosePriceX96;
    uint256 _totWeights = weeklyWeights[_prevWeeklyClose][_finalClosePriceX96];
    uint256 _rewardsETH = (_jackpotETH * rewardsPerc) / DENOMENATOR;
    if (_rewardsETH > 0 && rewards.totalSharesDeposited() > 0) {
      rewards.depositRewards{ value: _rewardsETH }();
    }

    uint256 _winningsETH;
    if (weeklyGuesses[_prevWeeklyClose][_finalClosePriceX96] > 0) {
      uint256 _totalWeeklyETH = (_jackpotETH * winningsPerc) / DENOMENATOR;
      uint256 _adminETH = (_totalWeeklyETH * adminPerc) / DENOMENATOR;
      if (_adminETH > 0) {
        uint256 _before = address(this).balance;
        (bool _success, ) = payable(adminWallet).call{ value: _adminETH }('');
        require(_success, 'SUBMIT0');
        require(address(this).balance >= _before - _adminETH, 'SUBMIT1');
      }
      uint256 _remainingWinningsETH = _totalWeeklyETH - _adminETH;
      // If any/all winners guessed very late in the weekly time window and total winning weights
      // are less than the maximum possible weight, reduce the winnings to be a percentage
      // of overall weights against the maximum possible.
      _winningsETH = _totWeights < maxGuessJackpotWeight
        ? (_remainingWinningsETH * _totWeights) / maxGuessJackpotWeight
        : _remainingWinningsETH;
    }
    winnersCircle.closeWeeklyAndAddWinnings{ value: _winningsETH }(
      _prevWeeklyClose,
      _finalClosePriceX96,
      _totWeights
    );

    emit SubmitWeeklyClose(
      _prevWeeklyClose,
      _finalClosePriceX96,
      totalWeeklyGuesses[_prevWeeklyClose],
      weeklyGuesses[_prevWeeklyClose][_finalClosePriceX96],
      _totWeights
    );
  }

  function getStartEndOfWeeklyGuessPeriod(
    uint256 _timestamp
  ) public view returns (uint256 start, uint256 end, uint256 span) {
    uint256 _followingWeeklyClose = getWeeklyCloseFromTimestamp(_timestamp);
    uint256 _weeklyCloseForGuess = _timestamp <
      _followingWeeklyClose - guessCutoffBeforeClose
      ? _followingWeeklyClose
      : getWeeklyCloseFromTimestamp(_timestamp + 7 days);

    start = _weeklyCloseForGuess - 7 days - guessCutoffBeforeClose;
    end = _weeklyCloseForGuess - guessCutoffBeforeClose;
    span = end - start;
  }

  function _getCurrentWinningsWeight() internal view returns (uint32) {
    uint32 _min = minGuessJackpotWeight;
    uint32 _max = maxGuessJackpotWeight;
    (uint256 _start, , uint256 _span) = getStartEndOfWeeklyGuessPeriod(
      block.timestamp
    );
    return
      uint32(_max - (((block.timestamp - _start) * (_max - _min)) / _span));
  }

  function _getSwapAtAmount() internal view returns (uint256) {
    return (totalSupply() * swapAtAmountSupplyPerc) / DENOMENATOR;
  }

  function _canReceiveRewards(address _wallet) internal view returns (bool) {
    return _wallet != address(0) && !rewardsExcluded[_wallet] && !amms[_wallet];
  }

  function burn(uint256 _amount) external {
    _burn(msg.sender, _amount);
    emit Burn(msg.sender, _amount);
  }

  // _fee: 3000 == 0.3%, 10000 == 1%
  // _initialPriceX96 = initialPrice * 2**96
  // initialPrice = token1Reserves / token0Reserves
  function lpCreatePool(
    uint24 _fee,
    uint256 _initialPriceX96,
    uint16 _initPriceObservations
  ) external onlyOwner {
    _createLiquidityPool(
      _fee,
      twapUtils.getSqrtPriceX96FromPriceX96(_initialPriceX96),
      _initPriceObservations
    );
  }

  // _fee: 3000 == 0.3%, 10000 == 1%
  // _percentTokenAllo: 50 == 50%, 100 == 100%
  function lpCreatePosition(
    uint24 _fee,
    uint8 _percentTokenAllo
  ) external payable onlyOwner {
    require(msg.value > 0, 'ADDLP0');
    require(_percentTokenAllo <= 100, 'ADDLP1');

    address _pool = _createLiquidityPosition(
      _fee,
      (balanceOf(address(this)) * _percentTokenAllo) / 100,
      msg.value
    );
    _setIsRewardsExcluded(_pool, true);
    amms[_pool] = true;
  }

  function launch() external onlyOwner {
    require(launchTime == 0, 'LAUNCH0');
    require(liquidityPosInitialized, 'LAUNCH1');
    launchTime = block.timestamp;
  }

  function submitClose() external {
    _checkAndSubmitPreviousWeeklyClose();
  }

  function buyTicket(uint256 _priceUSDX96) external {
    IERC20(address(this)).transferFrom(
      msg.sender,
      address(this),
      getCurrentPriceTokensPerTicket()
    );
    _buyTicket(msg.sender, _priceUSDX96);
  }

  function buyMultipleTickets(uint256[] memory _priceUSDX96) external {
    IERC20(address(this)).transferFrom(
      msg.sender,
      address(this),
      _priceUSDX96.length * getCurrentPriceTokensPerTicket()
    );
    for (uint256 _i = 0; _i < _priceUSDX96.length; _i++) {
      _buyTicket(msg.sender, _priceUSDX96[_i]);
    }
  }

  function getTotalJackpotBalance() public view returns (uint256) {
    return address(this).balance;
  }

  function getCurrentPriceTokensPerTicket() public view returns (uint256) {
    uint256 _min = pricePerTicketMinUSDX96;
    uint256 _max = pricePerTicketMaxUSDX96;
    (uint256 _start, , uint256 _span) = getStartEndOfWeeklyGuessPeriod(
      block.timestamp
    );
    uint256 _perTicketUSDX96 = _min +
      (((block.timestamp - _start) * (_max - _min)) / _span);
    return (_perTicketUSDX96 * 10 ** decimals()) / getCurrentPriceUSDX96();
  }

  function getCurrentPriceUSDX96() public view returns (uint256) {
    require(liquidityPosInitialized, 'INIT');
    (, , address _pool) = _getPoolInfo(_lpPoolFees[0]);
    return
      twapUtils.getPoolPriceUSDX96(
        address(this),
        _pool,
        address(nativeStablePool),
        WETH9,
        true
      );
  }

  function getPriceTokenPriceUSDX96() public view returns (uint256) {
    return
      twapUtils.getPoolPriceUSDX96(
        priceToken,
        address(pricePool),
        address(nativeStablePool),
        WETH9,
        _isPoolPairedWETH9
      );
  }

  function getWeeklyCloseFromTimestamp(
    uint256 _timestamp
  ) public pure returns (uint256) {
    uint256 _diffFromMidnight = _timestamp % 1 days;
    uint256 _thisComingMidnight = _timestamp + 1 days - _diffFromMidnight;
    uint256 _todayDOW = BokkyPooBahsDateTimeLibrary.getDayOfWeek(_timestamp);
    uint256 _daysUntilEOW = 7 - _todayDOW;
    return _thisComingMidnight + (_daysUntilEOW * 1 days) - 1;
  }

  function manualSwap() external onlyOwner {
    require(balanceOf(address(this)) >= _getSwapAtAmount(), 'SWAP0');
    _swapForETHAndProcess();
  }

  function setPriceTokenAndPool(
    address _token,
    IUniswapV3Pool _pool,
    bool _pairedWithWETH9
  ) external onlyOwner {
    address _token0 = _pool.token0();
    address _token1 = _pool.token1();
    require(_token0 == _token || _token1 == _token, 'BADTOKEN');
    priceToken = _token;
    pricePool = _pool;
    _isPoolPairedWETH9 = _pairedWithWETH9;
  }

  function toggleAmm(address _amm) external onlyOwner {
    amms[_amm] = !amms[_amm];
  }

  function forgiveBot(address _bot) external onlyOwner {
    require(isBot[_bot], 'FORGIVE0');
    isBot[_bot] = false;
  }

  function setTwapUtils(ITwapUtils _twapUtils) external onlyOwner {
    require(address(twapUtils) == address(0), 'SETTW');
    twapUtils = _twapUtils;
  }

  function setTickets(IGudGuessTickets _tickets) external onlyOwner {
    require(address(tickets) == address(0), 'SETT');
    tickets = _tickets;
  }

  function setWinnersCircle(IWinnersCircle _winnersCircle) external onlyOwner {
    require(address(winnersCircle) == address(0), 'SETWC');
    winnersCircle = _winnersCircle;
  }

  function setAdminWallet(address _adminWallet) external onlyOwner {
    adminWallet = _adminWallet;
  }

  function setBurnPerc(uint32 _perc) external onlyOwner {
    require(_perc <= DENOMENATOR, 'lte 100%');
    burnPerc = _perc;
  }

  function setRewardsPerc(uint32 _perc) external onlyOwner {
    require(_perc <= (DENOMENATOR * 10) / 100, 'lte 10%');
    rewardsPerc = _perc;
  }

  function setWinningsPerc(uint32 _perc) external onlyOwner {
    require(_perc <= (DENOMENATOR * 80) / 100, 'lte 80%');
    winningsPerc = _perc;
  }

  function setAdminPerc(uint32 _perc) external onlyOwner {
    require(_perc <= (DENOMENATOR * 5) / 100, 'lte 5%');
    adminPerc = _perc;
  }

  function setGuessJackpotWeights(uint32 _min, uint32 _max) external onlyOwner {
    require(_max > 0, 'WEIGHTS0');
    require(_min <= _max, 'WEIGHTS1');
    minGuessJackpotWeight = _min;
    maxGuessJackpotWeight = _max;
  }

  // _usd18: price per ticket in USD * 10**18
  // Example: $1.5/ticket = 1.5 * 10**18
  // Example: $2/ticket = 2 * 10**18
  function setPricePerTicketUSDX96(
    uint256 _minUSD18,
    uint256 _maxUSD18
  ) external onlyOwner {
    require(_minUSD18 <= _maxUSD18, 'PPT');
    pricePerTicketMinUSDX96 = (_minUSD18 * FixedPoint96.Q96) / 10 ** 18;
    pricePerTicketMaxUSDX96 = (_maxUSD18 * FixedPoint96.Q96) / 10 ** 18;
  }

  function setSwapAtAmountSupplyPerc(uint256 _supplyPerc) external onlyOwner {
    require(_supplyPerc > 0, 'SETSWAPAM0');
    require(_supplyPerc <= (DENOMENATOR * 2) / 100, 'SETSWAPAM1');
    swapAtAmountSupplyPerc = _supplyPerc;
  }

  function setSwapEnabled(bool _enabled) external onlyOwner {
    require(swapEnabled != _enabled, 'SWAPEN');
    swapEnabled = _enabled;
  }

  function setTaxEnabled(bool _enabled) external onlyOwner {
    require(taxEnabled != _enabled, 'TAXEN');
    taxEnabled = _enabled;
  }

  function setIsRewardsExcluded(
    address _wallet,
    bool _isExcluded
  ) external onlyOwner {
    _setIsRewardsExcluded(_wallet, _isExcluded);
  }

  function _setIsRewardsExcluded(address _wallet, bool _isExcluded) internal {
    require(rewardsExcluded[_wallet] != _isExcluded, 'SETEXCL');
    rewardsExcluded[_wallet] = _isExcluded;

    uint256 _walletBal = balanceOf(_wallet);
    if (_walletBal > 0) {
      bool _removeRewards = false;
      if (_isExcluded) {
        _removeRewards = true;
      }
      rewards.setShare(_wallet, _walletBal, _removeRewards);
    }
  }

  // We will round prices both at the weekly close and all guesses provided
  // by users in order to 1. allow for the ability to actually
  // guess the price & win the jackpot and 2. to store indexed value
  // of prices per guess on chain efficiently
  function setPrecisionDecimals(uint8 _decimals) external onlyOwner {
    precisionDecimals = _decimals;
  }

  function setGuessCutoffBeforeClose(uint256 _seconds) external onlyOwner {
    guessCutoffBeforeClose = _seconds;
  }

  function _afterTokenTransfer(
    address _from,
    address _to,
    uint256 _amount
  ) internal virtual {
    if (_canReceiveRewards(_from)) {
      rewards.setShare(_from, _amount, true);
    }
    if (_canReceiveRewards(_to)) {
      rewards.setShare(_to, _amount, false);
    }
  }
}

