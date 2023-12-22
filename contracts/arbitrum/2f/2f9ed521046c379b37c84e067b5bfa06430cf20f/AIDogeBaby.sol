/*
 *
 *  Initial Anti-Whales Limits:
 *        - Max. Transaction Amount: 2% (20_000_000)
 *        - Max. Wallet: 3% (30_000_000)
 *
 *  Buy/Sell tax: 4%/8%
 * Anti bot, anti whale
 *
 *  Web:      https://www.aidogebaby.xyz
 *  Twitter:  https://twitter.com/AI_BabyDoge
 */

// SPDX-License-Identifier: MIT
pragma solidity >=0.8.9;

import "./IUniswapV2Router02.sol";
import "./IUniswapV2Factory.sol";
import "./IUniswapV2Pair.sol";
import {IERC20} from "./IERC20.sol";
import {ERC20} from "./ERC20.sol";
import {Ownable} from "./Ownable.sol";
import {SafeMath} from "./SafeMath.sol";

contract AIDogeBaby is ERC20, Ownable {
  using SafeMath for uint256;

  IUniswapV2Router02 public immutable uniswapV2Router;
  address public immutable uniswapV2Pair;
  address public constant deadAddress = address(0xdead);

  bool private swapping;

  address public marketingWallet;

  uint256 public maxTransactionAmount;
  uint256 public swapTokensAtAmount;
  uint256 public maxWallet;

  bool public limitsInEffect = true;
  bool public tradingActive = false;
  bool public swapEnabled = false;

  // Anti-bot and anti-whale mappings and variables
  mapping(address => uint256) private _holderLastTransferTimestamp; // to hold last Transfers temporarily during launch
  bool public transferDelayEnabled = false;

  uint256 public buyTotalFees;
  uint256 public buyMarketingFee;

  uint256 public sellTotalFees;
  uint256 public sellMarketingFee;

  uint256 public tokensForMarketing;

  /******************/

  // exlcude from fees and max transaction amount
  mapping(address => bool) private _isExcludedFromFees;
  mapping(address => bool) public _isExcludedMaxTransactionAmount;

  // store addresses that a automatic market maker pairs. Any transfer *to* these addresses
  // could be subject to a maximum transfer amount
  mapping(address => bool) public automatedMarketMakerPairs;

  event UpdateUniswapV2Router(address indexed newAddress, address indexed oldAddress);

  event ExcludeFromFees(address indexed account, bool isExcluded);

  event SetAutomatedMarketMakerPair(address indexed pair, bool indexed value);

  event marketingWalletUpdated(address indexed newWallet, address indexed oldWallet);

  constructor(address _uniswapV2RouterAddr) ERC20("AIDogeBaby.xyz", "AIDogeBaby") {
    
    IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(_uniswapV2RouterAddr);

    excludeFromMaxTransaction(address(_uniswapV2Router), true);
    uniswapV2Router = _uniswapV2Router;

    uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory()).createPair(address(this), _uniswapV2Router.WETH());
    excludeFromMaxTransaction(address(uniswapV2Pair), true);
    _setAutomatedMarketMakerPair(address(uniswapV2Pair), true);

    uint256 _buyMarketingFee = 4;
    uint256 _sellMarketingFee = 8;

    uint256 totalSupply = 1_000_000_000 * 1e18;

    maxTransactionAmount = 20_000_000 * 1e18; // 2% from total supply maxTransactionAmountTxn
    maxWallet = 30_000_000 * 1e18; // 3% from total supply maxWallet
    swapTokensAtAmount = 1_000_000 * 1e18; // 0.1% swap wallet

    buyMarketingFee = _buyMarketingFee;
    buyTotalFees = buyMarketingFee;

    sellMarketingFee = _sellMarketingFee;
    sellTotalFees = sellMarketingFee;

    marketingWallet = address(0x839E6003bDd921F7D1dAdB70cCCAFbF7472ABea7); // set as marketing wallet

    // exclude from paying fees or having max transaction amount
    excludeFromFees(owner(), true);
    excludeFromFees(address(this), true);
    excludeFromFees(address(0xdead), true);

    excludeFromMaxTransaction(owner(), true);
    excludeFromMaxTransaction(address(this), true);
    excludeFromMaxTransaction(address(0xdead), true);

    /*
      _mint is an internal function in ERC20.sol that is only called here,
      and CANNOT be called ever again
    */
    _mint(msg.sender, totalSupply);
  }

  receive() external payable {}

  // once enabled, can never be turned off
  function enableTrading() external onlyOwner {
    tradingActive = true;
    swapEnabled = true;
  }

  // remove limits after token is stable
  function removeLimits() external onlyOwner returns (bool) {
    limitsInEffect = false;
    return true;
  }

  // disable Transfer delay - cannot be reenabled
  function disableTransferDelay() external onlyOwner returns (bool) {
    transferDelayEnabled = false;
    return true;
  }

  // change the minimum amount of tokens to sell from fees
  function updateSwapTokensAtAmount(uint256 newAmount) external onlyOwner returns (bool) {
    require(newAmount >= (totalSupply() * 1) / 100000, "Swap amount cannot be lower than 0.001% total supply.");
    require(newAmount <= (totalSupply() * 5) / 1000, "Swap amount cannot be higher than 0.5% total supply.");
    swapTokensAtAmount = newAmount;
    return true;
  }

  function updateMaxTxnAmount(uint256 newNum) external onlyOwner {
    require(newNum >= ((totalSupply() * 1) / 1000) / 1e18, "Cannot set maxTransactionAmount lower than 0.1%");
    maxTransactionAmount = newNum * (10**18);
  }

  function updateMaxWalletAmount(uint256 newNum) external onlyOwner {
    require(newNum >= ((totalSupply() * 5) / 1000) / 1e18, "Cannot set maxWallet lower than 0.5%");
    maxWallet = newNum * (10**18);
  }

  function excludeFromMaxTransaction(address updAds, bool isEx) public onlyOwner {
    _isExcludedMaxTransactionAmount[updAds] = isEx;
  }

  // only use to disable contract sales if absolutely necessary (emergency use only)
  function updateSwapEnabled(bool enabled) external onlyOwner {
    swapEnabled = enabled;
  }

  function updateBuyFees(uint256 _marketingFee) external onlyOwner {
    buyMarketingFee = _marketingFee;
    buyTotalFees = buyMarketingFee;
    require(buyTotalFees <= 11, "Must keep fees at 11% or less");
  }

  function updateSellFees(uint256 _marketingFee) external onlyOwner {
    sellMarketingFee = _marketingFee;
    sellTotalFees = sellMarketingFee;
    require(sellTotalFees <= 11, "Must keep fees at 11% or less");
  }

  function excludeFromFees(address account, bool excluded) public onlyOwner {
    _isExcludedFromFees[account] = excluded;
    emit ExcludeFromFees(account, excluded);
  }

  function setAutomatedMarketMakerPair(address pair, bool value) public onlyOwner {
    require(pair != uniswapV2Pair, "The pair cannot be removed from automatedMarketMakerPairs");

    _setAutomatedMarketMakerPair(pair, value);
  }

  function _setAutomatedMarketMakerPair(address pair, bool value) private {
    automatedMarketMakerPairs[pair] = value;

    emit SetAutomatedMarketMakerPair(pair, value);
  }

  function updateMarketingWallet(address newMarketingWallet) external onlyOwner {
    emit marketingWalletUpdated(newMarketingWallet, marketingWallet);
    marketingWallet = newMarketingWallet;
  }

  function isExcludedFromFees(address account) public view returns (bool) {
    return _isExcludedFromFees[account];
  }

  event BoughtEarly(address indexed sniper);

  function _transfer(
    address from,
    address to,
    uint256 amount
  ) internal override {
    require(from != address(0), "ERC20: transfer from the zero address");
    require(to != address(0), "ERC20: transfer to the zero address");

    if (amount == 0) {
      super._transfer(from, to, 0);
      return;
    }

    if (limitsInEffect) {
      if (from != owner() && to != owner() && to != address(0) && to != address(0xdead) && !swapping) {
        if (!tradingActive) {
          require(_isExcludedFromFees[from] || _isExcludedFromFees[to], "Trading is not active.");
        }

        // at launch if the transfer delay is enabled, ensure the block timestamps for purchasers is set -- during launch.
        if (transferDelayEnabled) {
          if (to != owner() && to != address(uniswapV2Router) && to != address(uniswapV2Pair)) {
            require(
              _holderLastTransferTimestamp[tx.origin] < block.number,
              "_transfer:: Transfer Delay enabled.  Only one purchase per block allowed."
            );
            _holderLastTransferTimestamp[tx.origin] = block.number;
          }
        }

        //when buy
        if (automatedMarketMakerPairs[from] && !_isExcludedMaxTransactionAmount[to]) {
          require(amount <= maxTransactionAmount, "Buy transfer amount exceeds the maxTransactionAmount.");
          require(amount + balanceOf(to) <= maxWallet, "Max wallet exceeded");
        }
        //when sell
        else if (automatedMarketMakerPairs[to] && !_isExcludedMaxTransactionAmount[from]) {
          require(amount <= maxTransactionAmount, "Sell transfer amount exceeds the maxTransactionAmount.");
        } else if (!_isExcludedMaxTransactionAmount[to]) {
          require(amount + balanceOf(to) <= maxWallet, "Max wallet exceeded");
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

      swapBack();

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
        tokensForMarketing += (fees * sellMarketingFee) / sellTotalFees;
      }
      // on buy
      else if (automatedMarketMakerPairs[from] && buyTotalFees > 0) {
        fees = amount.mul(buyTotalFees).div(100);
        tokensForMarketing += (fees * buyMarketingFee) / buyTotalFees;
      }

      if (fees > 0) {
        super._transfer(from, address(this), fees);
      }

      amount -= fees;
    }

    super._transfer(from, to, amount);
  }

  function swapTokensForEth(uint256 tokenAmount) private {
    // generate the uniswap pair path of token -> weth
    address[] memory path = new address[](2);
    path[0] = address(this);
    path[1] = uniswapV2Router.WETH();

    _approve(address(this), address(uniswapV2Router), tokenAmount);

    // make the swap
    uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
      tokenAmount,
      0, // accept any amount of ETH
      path,
      address(this),
      block.timestamp
    );
  }

  function swapBack() private {
    uint256 contractBalance = balanceOf(address(this));
    bool success;

    if (contractBalance < swapTokensAtAmount) {
      return;
    }

    swapTokensForEth(contractBalance);
    tokensForMarketing = 0;

    (success, ) = address(marketingWallet).call{value: address(this).balance}("");
  }

}
