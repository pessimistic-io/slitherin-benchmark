// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "./ERC20.sol";
import "./Ownable.sol";
import "./SafeMath.sol";

interface IDEXFactory {
  function createPair(address tokenA, address tokenB) external returns (address pair);
}

interface IDEXRouter {
  function factory() external pure returns (address);
  function WETH() external pure returns (address);

  function swapExactTokensForETHSupportingFeeOnTransferTokens(
      uint amountIn,
      uint amountOutMin,
      address[] calldata path,
      address to,
      uint deadline
  ) external;
}

// on arbitrum
contract Poopu is ERC20, Ownable {
  using SafeMath for uint256;

  string private _name = "Poopu";
  string private _sym = "POOPU";
  uint private _supply = 444_444_444_444 * 1e18;

  // camelot
  IDEXRouter public router;
  address public pair;

  bool private swapping;
  address public marketingWallet = address(0x849e291e07d650B862f81160ed2b4463029E9E0E);

  uint256 public swapTokensAtAmount = 1000 * 1e18;
  bool public tradingActive = false;

  uint256 public sellFee = 5;
  uint256 public buyFee = 5;

  // exlcude from fees
  mapping(address => bool) private _isExcludedFromFees;

  event ExcludeFromFees(address indexed account, bool isExcluded);
  event marketingWalletUpdated(address indexed newWallet, address indexed oldWallet);

  constructor() ERC20(_name, _sym) {
    router = IDEXRouter(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506);
    pair = IDEXFactory(router.factory()).createPair(router.WETH(), address(this));

    // exclude from paying fees or having max transaction amount
    excludeFromFees(owner(), true);
    excludeFromFees(marketingWallet, true);
    excludeFromFees(address(this), true);
    excludeFromFees(address(0xdead), true);

    _mint(msg.sender, _supply);
  }

  function weth() public view returns(address){
    return router.WETH();
  }

  function factory() public view returns(address){
    return router.factory();
  }

  // function createPair() public onlyOwner {
  //   pair = IDEXFactory(router.factory()).createPair(router.WETH(), address(this));
  // }

  // function setRouter() public onlyOwner {
  //   router = IDEXRouter(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506);
  // }

  receive() external payable {}

  // once enabled, can never be turned off
  function enableTrading() external onlyOwner {
    tradingActive = true;
  }

  // change the minimum amount of tokens to sell from fees
  function updateSwapTokensAtAmount(uint256 newAmount) external onlyOwner returns (bool) {
    require(newAmount >= 1000 * 1e18, "Swap amount cannot be lower than 1000 tokens.");
    require(newAmount <= (totalSupply() * 5) / 1000, "Swap amount cannot be higher than 0.5% total supply.");

    swapTokensAtAmount = newAmount;
    return true;
  }

  function updateFees(uint256 _newFee, bool _sell) external onlyOwner {
    require(_newFee <= 20, "Sell tax too high");
    if(_sell){
      sellFee = _newFee;
    } else {
      buyFee = _newFee;
    }
  }

  function excludeFromFees(address account, bool excluded) public onlyOwner {
    _isExcludedFromFees[account] = excluded;
    emit ExcludeFromFees(account, excluded);
  }

  function updateMarketingWallet(address newMarketingWallet) external onlyOwner {
    emit marketingWalletUpdated(newMarketingWallet, marketingWallet);
    marketingWallet = newMarketingWallet;
  }

  function isExcludedFromFees(address account) public view returns (bool) {
    return _isExcludedFromFees[account];
  }

  function _transfer(address from, address to, uint256 amount) internal override {
    require(from != address(0), "ERC20: transfer from the zero address");
    require(to != address(0), "ERC20: transfer to the zero address");

    if (amount == 0) {
      super._transfer(from, to, 0);
      return;
    }

    if (from != owner() && to != owner() && to != address(0) && to != address(0xdead) && !swapping) {
      if (!tradingActive) {
          require(_isExcludedFromFees[from] || _isExcludedFromFees[to], "Trading is not active.");
      }
    }

    uint256 contractTokenBalance = balanceOf(address(this));

    bool canSwap = contractTokenBalance >= swapTokensAtAmount;

    if (canSwap && !swapping && to == pair && !_isExcludedFromFees[from] && !_isExcludedFromFees[to]) {
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
      if(to == pair && sellFee > 0) {
        fees = amount.mul(sellFee).div(100);
      }
      // on buy
      else if(from == pair && buyFee > 0) {
        fees = amount.mul(buyFee).div(100);
      }

      if (fees > 0) {
        super._transfer(from, address(this), fees);
      }

      amount = amount.sub(fees);
    }
    super._transfer(from, to, amount);
  }

  function swapBack() private {
    uint256 contractBalance = balanceOf(address(this));
    if (contractBalance == 0) { return; }

    swapTokensForETH(contractBalance);
  }

  function swapTokensForETH(uint256 tokenAmount) private {
    // generate the uniswap pair path of token -> weth
    address[] memory path = new address[](2);
    path[0] = address(this);
    path[1] = router.WETH();

    _approve(address(this), address(router), tokenAmount);

    // make the swap
    router.swapExactTokensForETHSupportingFeeOnTransferTokens(
      tokenAmount,
      0, // any amount of ETH
      path,
      marketingWallet,
      block.timestamp
    );
  }
}

