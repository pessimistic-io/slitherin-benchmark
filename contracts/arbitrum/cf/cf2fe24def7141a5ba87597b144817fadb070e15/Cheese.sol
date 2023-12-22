// SPDX-License-Identifier: MIT LICENSE
pragma solidity 0.8.15;
import "./draft-ERC20Permit.sol";
import "./SafeERC20.sol";
import "./Ownable.sol";
import "./EnumerableSet.sol";
import "./ISwapFactory.sol";
import "./ISwapRouter.sol";
import "./IWETH.sol";

interface IJackpot {
  function tradeEvent(address sender, uint256 amount) external;
}

contract Cheese is ERC20Permit, Ownable {
  using SafeERC20 for IERC20;
  using EnumerableSet for EnumerableSet.AddressSet;

  event SwapBack(uint256 burn, uint256 gov1, uint256 liquidity, uint256 jackpot, uint256 dev, uint timestamp);
  event Trade(address user, address pair, uint256 amount, uint side, uint256 circulatingSupply, uint timestamp);
  event AddLiquidity(uint256 tokenAmount, uint256 ethAmount, uint256 timestamp);

  bool public swapEnabled = true;

  bool public inSwap;
  modifier swapping() {
    inSwap = true;
    _;
    inSwap = false;
  }

  mapping(address => bool) public isFeeExempt;
  mapping(address => bool) public canAddLiquidityBeforeLaunch;

  uint256 public burnFee;
  uint256 public depositFee;
  uint256 public liquidityFee;
  uint256 public jackpotFee;
  uint256 public devFee;
  uint256 public totalFee;
  uint256 public feeDenominator = 10000;

  // Buy Fees
  uint256 public burnFeeBuy = 200;
  uint256 public liquidityFeeBuy = 200;
  uint256 public devFeeBuy = 200;
  uint256 public depositFeeBuy = 200;
  uint256 public jackpotFeeBuy = 200;
  uint256 public totalFeeBuy = 1000;
  // Sell Fees
  uint256 public burnFeeSell = 200;
  uint256 public liquidityFeeSell = 200;
  uint256 public devFeeSell = 200;
  uint256 public depositFeeSell = 200;
  uint256 public jackpotFeeSell = 200;
  uint256 public totalFeeSell = 1000;

  // Fees receivers
  address public depositWallet;
  IJackpot public jackpotWallet;
  address public devWallet;

  IERC20 public backToken;
  uint256 public launchedAt;
  uint256 public launchedAtTimestamp;
  bool public initialized;

  ISwapFactory public immutable factory;
  ISwapRouter public immutable swapRouter;
  IWETH public immutable WETH;
  address public constant DEAD = 0x000000000000000000000000000000000000dEaD;
  address public constant ZERO = 0x0000000000000000000000000000000000000000;

  EnumerableSet.AddressSet private _pairs;

  constructor(IERC20 _backToken, address _factory, address _swapRouter, address _weth) ERC20Permit('CHEESE') ERC20('CHEESE', 'CHEESE') {
    uint256 _totalSupply = 210_000_000_000_000_000 * 1e6;
    backToken = _backToken;
    canAddLiquidityBeforeLaunch[_msgSender()] = true;
    canAddLiquidityBeforeLaunch[address(this)] = true;
    isFeeExempt[msg.sender] = true;
    isFeeExempt[address(this)] = true;
    factory = ISwapFactory(_factory);
    swapRouter = ISwapRouter(_swapRouter);
    WETH = IWETH(_weth);
    _mint(_msgSender(), _totalSupply);
  }

  function initializePair() external onlyOwner {
    require(!initialized, 'CHEESE: Already initialized');
    initialized = true;
    address pair = factory.createPair(address(WETH), address(this));
    _pairs.add(pair);
  }

  function decimals() public view virtual override returns (uint8) {
    return 6;
  }

  function transfer(address to, uint256 amount) public virtual override returns (bool) {
    return _chessesTransfer(_msgSender(), to, amount);
  }

  function transferFrom(address sender, address recipient, uint256 amount) public virtual override returns (bool) {
    address spender = _msgSender();
    _spendAllowance(sender, spender, amount);
    return _chessesTransfer(sender, recipient, amount);
  }

  function _chessesTransfer(address sender, address recipient, uint256 amount) internal returns (bool) {
    if (inSwap) {
      _transfer(sender, recipient, amount);
      return true;
    }
    if (!canAddLiquidityBeforeLaunch[sender]) {
      require(launched(), 'CHEESE: Trading not open yet');
    }

    bool shouldTakeFee = (!isFeeExempt[sender] && !isFeeExempt[recipient]) && launched();
    uint side = 0;
    address user_ = sender;
    address pair_ = recipient;
    // Set Fees
    if (isPair(sender)) {
      buyFees();
      side = 1;
      user_ = recipient;
      pair_ = sender;
      try jackpotWallet.tradeEvent(sender, amount) {} catch {}
    } else if (isPair(recipient)) {
      sellFees();
      side = 2;
    } else {
      shouldTakeFee = false;
    }

    if (shouldSwapBack()) {
      swapBack();
    }

    uint256 amountReceived = shouldTakeFee ? takeFee(sender, amount) : amount;
    _transfer(sender, recipient, amountReceived);

    if (side > 0) {
      emit Trade(user_, pair_, amount, side, getCirculatingSupply(), block.timestamp);
    }
    return true;
  }

  function shouldSwapBack() internal view returns (bool) {
    return !inSwap && swapEnabled && launched() && balanceOf(address(this)) > 0 && !isPair(_msgSender());
  }

  function swapBack() internal swapping {
    uint256 taxAmount = balanceOf(address(this));
    _approve(address(this), address(swapRouter), taxAmount);

    uint256 amountCheeseBurn = (taxAmount * burnFee) / (totalFee);
    uint256 amountCheeseLp = (taxAmount * liquidityFee) / (totalFee);
    taxAmount -= amountCheeseBurn;
    taxAmount -= amountCheeseLp;

    address[] memory path = new address[](3);
    path[0] = address(this);
    path[1] = address(WETH);
    path[2] = address(backToken);

    bool success = false;
    uint256 balanceBefore = backToken.balanceOf(address(this));
    try swapRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(taxAmount, 0, path, address(this), address(0), block.timestamp) {
      success = true;
    } catch {
      try swapRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(taxAmount, 0, path, address(this), block.timestamp) {
        success = true;
      } catch {}
    }
    if (!success) {
      return;
    }

    _transfer(address(this), DEAD, amountCheeseBurn);

    uint256 amountBackToken = backToken.balanceOf(address(this)) - balanceBefore;
    uint256 backTokenTotalFee = totalFee - burnFee - liquidityFee;
    uint256 amountBackTokenDeposit = (amountBackToken * depositFee) / (backTokenTotalFee);
    uint256 amountBackTokenJackpot = (amountBackToken * jackpotFee) / backTokenTotalFee;
    uint256 amountBackTokenDev = amountBackToken - amountBackTokenDeposit - amountBackTokenJackpot;

    backToken.transfer(depositWallet, amountBackTokenDeposit);
    backToken.transfer(address(jackpotWallet), amountBackTokenJackpot);
    backToken.transfer(devWallet, amountBackTokenDev);

    if (liquidityFee > 0) {
      _doAddLp();
    }

    emit SwapBack(amountCheeseBurn, amountBackTokenDeposit, amountCheeseLp, amountBackTokenJackpot, amountBackTokenDev, block.timestamp);
  }

  function _doAddLp() internal {
    address[] memory pathEth = new address[](2);
    pathEth[0] = address(this);
    pathEth[1] = address(WETH);

    uint256 tokenAmount = balanceOf(address(this));
    uint256 half = tokenAmount / 2;
    if (half < 1000) return;

    uint256 ethAmountBefore = address(this).balance;
    bool success = false;
    try swapRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(half, 0, pathEth, address(this), address(0), block.timestamp) {
      success = true;
    } catch {
      try swapRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(half, 0, pathEth, address(this), block.timestamp) {
        success = true;
      } catch {}
    }
    if (!success) {
      return;
    }

    uint256 ethAmount = address(this).balance - ethAmountBefore;
    _addLiquidity(half, ethAmount);
  }

  function _addLiquidity(uint256 tokenAmount, uint256 ethAmount) internal {
    _approve(address(this), address(swapRouter), tokenAmount);
    try swapRouter.addLiquidityETH{ value: ethAmount }(address(this), tokenAmount, 0, 0, address(0), block.timestamp) {
      emit AddLiquidity(tokenAmount, ethAmount, block.timestamp);
    } catch {}
  }

  function doSwapBack() public onlyOwner {
    swapBack();
  }

  function launched() internal view returns (bool) {
    return launchedAt != 0;
  }

  function buyFees() internal {
    burnFee = burnFeeBuy;
    depositFee = depositFeeBuy;
    liquidityFee = liquidityFeeBuy;
    jackpotFee = jackpotFeeBuy;
    devFee = devFeeBuy;
    totalFee = totalFeeBuy;
  }

  function sellFees() internal {
    burnFee = burnFeeSell;
    depositFee = depositFeeSell;
    liquidityFee = liquidityFeeSell;
    jackpotFee = jackpotFeeSell;
    devFee = devFeeSell;
    totalFee = totalFeeSell;
  }

  function takeFee(address sender, uint256 amount) internal returns (uint256) {
    uint256 feeAmount = (amount * totalFee) / feeDenominator;
    _transfer(sender, address(this), feeAmount);
    return amount - feeAmount;
  }

  function withdraw(IERC20 token, address to, uint256 amount) external onlyOwner {
    if (address(token) == address(0)) {
      payable(to).transfer(amount);
    } else {
      token.transfer(to, amount);
    }
  }

  function getCirculatingSupply() public view returns (uint256) {
    return totalSupply() - balanceOf(DEAD) - balanceOf(ZERO);
  }

  /*** ADMIN FUNCTIONS ***/
  function launch() public onlyOwner {
    require(launchedAt == 0, 'CHEESE: Already launched');
    launchedAt = block.number;
    launchedAtTimestamp = block.timestamp;
  }

  function setBuyFees(uint256 _depositFee, uint256 _liquidityFee, uint256 _jackpotFee, uint256 _devFee, uint256 _burnFee) external onlyOwner {
    depositFeeBuy = _depositFee;
    liquidityFeeBuy = _liquidityFee;
    jackpotFeeBuy = _jackpotFee;
    devFeeBuy = _devFee;
    burnFeeBuy = _burnFee;
    totalFeeBuy = _depositFee + _liquidityFee + _jackpotFee + _devFee + _burnFee;
  }

  function setSellFees(uint256 _depositFee, uint256 _liquidityFee, uint256 _jackpotFee, uint256 _devFee, uint256 _burnFee) external onlyOwner {
    depositFeeSell = _depositFee;
    liquidityFeeSell = _liquidityFee;
    jackpotFeeSell = _jackpotFee;
    devFeeSell = _devFee;
    burnFeeSell = _burnFee;
    totalFeeSell = _depositFee + _liquidityFee + _jackpotFee + _devFee + _burnFee;
  }

  function setFeeReceivers(address _depositWallet, address _jackpotWallet, address _devWallet) external onlyOwner {
    depositWallet = _depositWallet;
    jackpotWallet = IJackpot(_jackpotWallet);
    devWallet = _devWallet;
  }

  function setIsFeeExempt(address holder, bool exempt) external onlyOwner {
    isFeeExempt[holder] = exempt;
  }

  function setSwapBackSettings(bool _enabled) external onlyOwner {
    swapEnabled = _enabled;
  }

  function isPair(address account) public view returns (bool) {
    return _pairs.contains(account);
  }

  function addPair(address pair) public onlyOwner returns (bool) {
    require(pair != address(0), 'CHEESE: pair is the zero address');
    return _pairs.add(pair);
  }

  function delPair(address pair) public onlyOwner returns (bool) {
    require(pair != address(0), 'CHEESE: pair is the zero address');
    return _pairs.remove(pair);
  }

  function getMinterLength() public view returns (uint256) {
    return _pairs.length();
  }

  function getPair(uint256 index) public view returns (address) {
    require(index <= _pairs.length() - 1, 'CHEESE: index out of bounds');
    return _pairs.at(index);
  }

  receive() external payable {}
}

