/**
 * 
 * JackBot is a revolutionary Telegram bot that combines crypto with the thrill of seamless, fast and cheap betting on fun casino games. 
 * Say goodbye to traditional hassles and embrace lightning fast betting with instant payouts straight from your Telegram app!
 * Fuel your excitement with our on chain TG betting bot deployed on Arbitrum
 * zero to none fees, no delays, all action!
 *
**/

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./IJackBotRevenue.sol";
import "./ERC20.sol";
import "./Ownable.sol";
import "./SafeMath.sol";

contract JackBot is ERC20, Ownable {
  using SafeMath for uint256;

  IJackBotRevenue public jackBotRevenue;

  bool private swapping;

  address public revShareWallet;
  address public teamWallet;
  address public bankrollWallet;

  uint256 public maxTransactionAmount;
  uint256 public swapTokensAtAmount;
  uint256 public maxWallet;

  bool public canUpdateJackBotRevenue = true;
  bool public limitsInEffect = true;
  bool public tradingActive = false;
  bool public swapEnabled = false;

  bool public blacklistRenounced = false;

  // Anti-bot and anti-whale mappings and variables
  mapping(address => bool) blacklisted;

  uint256 public buyTotalFees;
  uint256 public buyRevShareFee;
  uint256 public buyLiquidityFee;
  uint256 public buyTeamFee;
  uint256 public buyBankrollFee;

  uint256 public sellTotalFees;
  uint256 public sellRevShareFee;
  uint256 public sellLiquidityFee;
  uint256 public sellTeamFee;
  uint256 public sellBankrollFee;

  uint256 public tokensForRevShare;
  uint256 public tokensForLiquidity;
  uint256 public tokensForTeam;
  uint256 public tokensForBankroll;

  /******************/

  // exclude from fees and max transaction amount
  mapping(address => bool) private _isExcludedFromFees;
  mapping(address => bool) public _isExcludedMaxTransactionAmount;

  // store addresses that a automatic market maker pairs. Any transfer *to* these addresses
  // could be subject to a maximum transfer amount
  mapping(address => bool) public automatedMarketMakerPairs;

  bool public preMigrationPhase = true;
  mapping(address => bool) public preMigrationTransferrable;

  event ExcludeFromFees(address indexed account, bool isExcluded);

  event SetAutomatedMarketMakerPair(address indexed pair, bool indexed value);

  event revShareWalletUpdated(
    address indexed newWallet,
    address indexed oldWallet
  );

  event bankrollWalletUpdated(
    address indexed newWallet,
    address indexed oldWallet
  );

  event teamWalletUpdated(
    address indexed newWallet,
    address indexed oldWallet
  );

  // After deployment:
  // Create pool JACKBOT/WETH with 30 bp fees
  // Fee amounts are hundredths of the basis point. That is, 1 fee unit is 0.0001%, 500 is 0.05%, and 3000 is 0.3%.
  // Then run
  // excludeFromMaxTransaction(address(uniswapV3Pair), true);
  // _setAutomatedMarketMakerPair(address(uniswapV3Pair), true);
  constructor() ERC20("JackBot", "JACKBOT") {
    uint256 _buyRevShareFee = 1;
    uint256 _buyLiquidityFee = 1;
    uint256 _buyTeamFee = 1;
    uint256 _buyBankrollFee = 1;

    uint256 _sellRevShareFee = 1;
    uint256 _sellLiquidityFee = 1;
    uint256 _sellTeamFee = 1;
    uint256 _sellBankrollFee = 1;

    uint256 totalSupply = 100_000_000 * 1e18;

    maxTransactionAmount = 1_000_000 * 1e18; // 1%
    maxWallet = 1_000_000 * 1e18; // 1% 
    swapTokensAtAmount = (totalSupply * 5) / 10000; // 0.05% 

    buyRevShareFee = _buyRevShareFee;
    buyLiquidityFee = _buyLiquidityFee;
    buyTeamFee = _buyTeamFee;
    buyBankrollFee = _buyBankrollFee;
    buyTotalFees = buyBankrollFee + buyRevShareFee + buyLiquidityFee + buyTeamFee;

    sellRevShareFee = _sellRevShareFee;
    sellLiquidityFee = _sellLiquidityFee;
    sellTeamFee = _sellTeamFee;
    sellBankrollFee = _sellBankrollFee;
    sellTotalFees = sellBankrollFee + sellRevShareFee + sellLiquidityFee + sellTeamFee;

    revShareWallet = 0x16344A66A06cE8F77E2a56E5a61eCeed24D35Ff2;
    bankrollWallet = 0xe278b1a1CCDF8B7CDBE545ce3d38aa57A969AF14;
    teamWallet = owner(); // set as team wallet

    // exclude from paying fees or having max transaction amount
    excludeFromFees(owner(), true);
    excludeFromFees(address(this), true);
    excludeFromFees(address(0xdead), true);

    excludeFromMaxTransaction(owner(), true);
    excludeFromMaxTransaction(address(this), true);
    excludeFromMaxTransaction(address(0xdead), true);

    preMigrationTransferrable[owner()] = true;

    /*
      _mint is an internal function in ERC20.sol that is only called here, and CANNOT be called ever again
    */
    _mint(msg.sender, totalSupply);
  }

  receive() external payable {}

  // once enabled, can never be turned off
  function enableTrading() external onlyOwner {
    tradingActive = true;
    swapEnabled = true;
    preMigrationPhase = false;
  }

  function disableJackBotRevenueUpdates() external onlyOwner {
    canUpdateJackBotRevenue = false;
  }

  function updateJackBotRevenue(address newJackBotRevenue) external onlyOwner {
    require(canUpdateJackBotRevenue, "Can no longer update JackBot Revenue logic");

    jackBotRevenue = IJackBotRevenue(newJackBotRevenue);
  }

  // remove limits after token is stable
  function removeLimits() external onlyOwner returns (bool) {
    limitsInEffect = false;
    return true;
  }

  // change the minimum amount of tokens to sell from fees
  function updateSwapTokensAtAmount(uint256 newAmount) external onlyOwner returns (bool) {
    require(
      newAmount >= (totalSupply() * 1) / 100000,
      "Swap amount cannot be lower than 0.001% total supply."
    );
    require(
      newAmount <= (totalSupply() * 5) / 1000,
      "Swap amount cannot be higher than 0.5% total supply."
    );
    swapTokensAtAmount = newAmount;
    return true;
  }

  function updateMaxTxnAmount(uint256 newNum) external onlyOwner {
    require(
      newNum >= ((totalSupply() * 5) / 1000) / 1e18,
       "Cannot set maxTransactionAmount lower than 0.5%"
    );
    maxTransactionAmount = newNum * (10**18);
  }

  function updateMaxWalletAmount(uint256 newNum) external onlyOwner {
    require(
      newNum >= ((totalSupply() * 10) / 1000) / 1e18,
      "Cannot set maxWallet lower than 1.0%"
    );
    maxWallet = newNum * (10**18);
  }

  function excludeFromMaxTransaction(address updAds, bool isEx) public onlyOwner {
    _isExcludedMaxTransactionAmount[updAds] = isEx;
  }

  // only use to disable contract sales if absolutely necessary (emergency use only)
  function updateSwapEnabled(bool enabled) external onlyOwner {
    swapEnabled = enabled;
  }

  function updateBuyFees(
    uint256 _revShareFee,
    uint256 _liquidityFee,
    uint256 _teamFee,
    uint256 _bankrollFee
  ) external onlyOwner {
    buyRevShareFee = _revShareFee;
    buyLiquidityFee = _liquidityFee;
    buyTeamFee = _teamFee;
    buyBankrollFee = _bankrollFee;
    buyTotalFees = buyBankrollFee + buyRevShareFee + buyLiquidityFee + buyTeamFee;
    require(buyTotalFees <= 5, "Buy fees must be <= 5.");
  }

  function updateSellFees(
    uint256 _revShareFee,
    uint256 _liquidityFee,
    uint256 _teamFee,
    uint256 _bankrollFee
  ) external onlyOwner {
    sellRevShareFee = _revShareFee;
    sellLiquidityFee = _liquidityFee;
    sellTeamFee = _teamFee;
    sellBankrollFee = _bankrollFee;
    sellTotalFees = sellBankrollFee + sellRevShareFee + sellLiquidityFee + sellTeamFee;
    require(sellTotalFees <= 5, "Sell fees must be <= 5.");
  }

  function excludeFromFees(address account, bool excluded) public onlyOwner {
    _isExcludedFromFees[account] = excluded;
    emit ExcludeFromFees(account, excluded);
  }

  function setAutomatedMarketMakerPair(address pair, bool value) public onlyOwner {
    _setAutomatedMarketMakerPair(pair, value);
  }

  function _setAutomatedMarketMakerPair(address pair, bool value) private {
    automatedMarketMakerPairs[pair] = value;

    emit SetAutomatedMarketMakerPair(pair, value);
  }

  function updateRevShareWallet(address newRevShareWallet) external onlyOwner {
    emit revShareWalletUpdated(newRevShareWallet, revShareWallet);
    revShareWallet = newRevShareWallet;
  }

  function updateBankrollWallet(address newBankrollWallet) external onlyOwner {
    emit bankrollWalletUpdated(newBankrollWallet, bankrollWallet);
    bankrollWallet = newBankrollWallet;
  }

  function updateTeamWallet(address newWallet) external onlyOwner {
    emit teamWalletUpdated(newWallet, teamWallet);
    teamWallet = newWallet;
  }

  function isExcludedFromFees(address account) public view returns (bool) {
    return _isExcludedFromFees[account];
  }

  function isBlacklisted(address account) public view returns (bool) {
    return blacklisted[account];
  }

  function _transfer(address from, address to, uint256 amount) internal override {
    require(from != address(0), "ERC20: transfer from the zero address");
    require(to != address(0), "ERC20: transfer to the zero address");
    require(!blacklisted[from],"Sender blacklisted");
    require(!blacklisted[to],"Receiver blacklisted");

    if (preMigrationPhase) {
      require(preMigrationTransferrable[from], "Not authorized to transfer pre-migration.");
    }

    if (amount == 0) {
      super._transfer(from, to, 0);
      return;
    }

    if (limitsInEffect) {
      if (
        from != owner() &&
        to != owner() &&
        to != address(0) &&
        to != address(0xdead) &&
        !swapping
      ) {
        if (!tradingActive) {
          require(
            _isExcludedFromFees[from] || _isExcludedFromFees[to],
            "Trading is not active."
          );
        }

        //when buy
        if (automatedMarketMakerPairs[from] && !_isExcludedMaxTransactionAmount[to]) {
          require(
            amount <= maxTransactionAmount,
            "Buy transfer amount exceeds the maxTransactionAmount."
          );
          require(
            amount + balanceOf(to) <= maxWallet,
            "Max wallet exceeded"
          );
        } else if (
          automatedMarketMakerPairs[to] &&
          !_isExcludedMaxTransactionAmount[from]
        ) {
          require(
            amount <= maxTransactionAmount,
            "Sell transfer amount exceeds the maxTransactionAmount."
          );
        } else if (!_isExcludedMaxTransactionAmount[to]) {
          require(
            amount + balanceOf(to) <= maxWallet,
            "Max wallet exceeded"
          );
        }
      }
    }

    uint256 contractTokenBalance = balanceOf(address(this));

    bool canSwap = contractTokenBalance >= swapTokensAtAmount;

    if (
      canSwap &&
      swapEnabled &&
      !swapping &&
      !automatedMarketMakerPairs[from] &&
      !_isExcludedFromFees[from] &&
      !_isExcludedFromFees[to]
    ) {
      swapping = true;
      if (contractTokenBalance > swapTokensAtAmount * 20) {
        contractTokenBalance = swapTokensAtAmount * 20;
      }
      super._transfer(address(this), address(jackBotRevenue), contractTokenBalance);
      jackBotRevenue.swapBack(
        contractTokenBalance,
        tokensForBankroll,
        tokensForLiquidity,
        tokensForRevShare,
        tokensForTeam,
        swapTokensAtAmount,
        teamWallet,
        revShareWallet,
        bankrollWallet
      );
      swapping = false;
    }

    bool takeFee = !swapping;

    // if any account belongs to _isExcludedFromFee account then remove the fee
    if (_isExcludedFromFees[from] || _isExcludedFromFees[to]) {
      takeFee = false;
    }

    uint256 fees = 0;
    // only take fees on buys/sells, do not take on wallet transfers
    if (takeFee) {
      // on sell
      if (automatedMarketMakerPairs[to] && sellTotalFees > 0) {
        fees = amount.mul(sellTotalFees).div(100);
        tokensForLiquidity += (fees * sellLiquidityFee) / sellTotalFees;
        tokensForTeam += (fees * sellTeamFee) / sellTotalFees;
        tokensForRevShare += (fees * sellRevShareFee) / sellTotalFees;
        tokensForBankroll += (fees * sellBankrollFee) / sellTotalFees;
      }
      // on buy
      else if (automatedMarketMakerPairs[from] && buyTotalFees > 0) {
        fees = amount.mul(buyTotalFees).div(100);
        tokensForLiquidity += (fees * buyLiquidityFee) / buyTotalFees;
        tokensForTeam += (fees * buyTeamFee) / buyTotalFees;
        tokensForRevShare += (fees * buyRevShareFee) / buyTotalFees;
        tokensForBankroll += (fees * buyBankrollFee) / buyTotalFees;
      }

      if (fees > 0) {
        super._transfer(from, address(this), fees);
      }

      amount -= fees;
    }

    super._transfer(from, to, amount);
  }

  function withdrawStuckJackbot() external onlyOwner {
    uint256 balance = IERC20(address(this)).balanceOf(address(this));
    IERC20(address(this)).transfer(msg.sender, balance);
    payable(msg.sender).transfer(address(this).balance);
  }

  function withdrawStuckToken(address _token, address _to) external onlyOwner {
    require(_token != address(0), "_token address cannot be 0");
    uint256 _contractBalance = IERC20(_token).balanceOf(address(this));
    IERC20(_token).transfer(_to, _contractBalance);
  }

  function withdrawStuckEth(address toAddr) external onlyOwner {
    (bool success, ) = toAddr.call{value: address(this).balance} ("");
    require(success);
  }

  // @dev team renounce blacklist commands
  function renounceBlacklist() public onlyOwner {
    blacklistRenounced = true;
  }

  function blacklist(address _addr) public onlyOwner {
    require(!blacklistRenounced, "Team has revoked blacklist rights");
    require(
      _addr != address(0xc873fEcbd354f5A56E00E710B90EF4201db2448d), 
      "Cannot blacklist token's v3 router."
    );
    blacklisted[_addr] = true;
  }

  // @dev unblacklist address; not affected by blacklistRenounced incase team wants to unblacklist v3 pools down the road
  function unblacklist(address _addr) public onlyOwner {
    blacklisted[_addr] = false;
  }

  function setPreMigrationTransferable(address _addr, bool isAuthorized) public onlyOwner {
    preMigrationTransferrable[_addr] = isAuthorized;
    excludeFromFees(_addr, isAuthorized);
    excludeFromMaxTransaction(_addr, isAuthorized);
  }
}

