// NitroPad Token
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./DividendDistributor.sol";
import "./IUniswapV2Factory.sol";
import "./Auth.sol";

contract NitroPad is IERC20, Auth {
  using SafeMath for uint256;

  address private constant ROUTER = 0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506;
  address private constant DEAD = 0x000000000000000000000000000000000000dEaD;
  address private constant ZERO = 0x0000000000000000000000000000000000000000;

  string private constant _name = "NitroPad";
  string private constant _symbol = "NPAD";
  uint8 private constant _decimals = 18;

  uint256 private _totalSupply = 1_000_000 * (10**_decimals);
  uint256 public _maxTxAmount = _totalSupply.div(400); // 0.25% (2_500)
  uint256 public _maxWallet = _totalSupply.div(40); // 2.5% (25_000)

  mapping(address => uint256) private _balances;
  mapping(address => mapping(address => uint256)) private _allowances;

  mapping(address => bool) public isFeeExempt;
  mapping(address => bool) public isTxLimitExempt;
  mapping(address => bool) public isDividendExempt;
  mapping(address => bool) public canAddLiquidityBeforeLaunch;

  uint256 private liquidityFee;
  uint256 private buybackFee;
  uint256 private reflectionFee;
  uint256 private investmentFee;
  uint256 private totalFee;
  uint256 public feeDenominator = 10000;

  // Buy Fees
  uint256 public liquidityFeeBuy = 0;
  uint256 public buybackFeeBuy = 0;
  uint256 public reflectionFeeBuy = 0;
  uint256 public investmentFeeBuy = 400;
  uint256 public totalFeeBuy = 400; // 5%
  // Sell Fees
  uint256 public liquidityFeeSell = 0;
  uint256 public buybackFeeSell = 0;
  uint256 public reflectionFeeSell = 0;
  uint256 public investmentFeeSell = 400;
  uint256 public totalFeeSell = 400; // 5%
  // Transfer Fees
  uint256 public liquidityFeeTransfer = 0;
  uint256 public buybackFeeTransfer = 0;
  uint256 public reflectionFeeTransfer = 0;
  uint256 public investmentFeeTransfer = 0;
  uint256 public totalFeeTransfer = 0; // 0%

  uint256 public targetLiquidity = 10;
  uint256 public targetLiquidityDenominator = 100;

  IUniswapV2Router02 public router;
  address public pair;

  uint256 public launchedAt;
  uint256 public launchedAtTimestamp;

  // Fees receivers
  address public autoLiquidityReceiver = 0xF233d122F96fFb3A283E712B4c439cba176C548d;
  address public investmentFeeReceiver = 0x3dF475F4c39912e142955265e8f5c38dAd286FE3;

  bool public autoBuybackEnabled = false;
  uint256 public autoBuybackCap;
  uint256 public autoBuybackAccumulator;
  uint256 public autoBuybackAmount;
  uint256 public autoBuybackBlockPeriod;
  uint256 public autoBuybackBlockLast;

  DividendDistributor public distributor;
  address public distributorAddress;
  uint256 private distributorGas = 200000;

  bool public swapEnabled = true;
  uint256 public swapThreshold = _totalSupply / 2000; // 0.05% (500)
  bool public inSwap;
  modifier swapping() {
    inSwap = true;
    _;
    inSwap = false;
  }

  constructor() Auth(msg.sender) {
    router = IUniswapV2Router02(ROUTER);
    pair = IUniswapV2Factory(router.factory()).createPair(router.WETH(), address(this));
    _allowances[address(this)][address(router)] = _totalSupply;

    distributor = new DividendDistributor(address(router));
    distributorAddress = address(distributor);

    isFeeExempt[msg.sender] = true;
    isTxLimitExempt[msg.sender] = true;

    canAddLiquidityBeforeLaunch[msg.sender] = true;

    isDividendExempt[pair] = true;
    isDividendExempt[address(this)] = true;
    isDividendExempt[DEAD] = true;

    approve(address(router), _totalSupply);
    approve(address(pair), _totalSupply);
    _balances[msg.sender] = _totalSupply;
    emit Transfer(address(0), msg.sender, _totalSupply);
  }

  receive() external payable {}

  function totalSupply() external view override returns (uint256) {
    return _totalSupply;
  }

  function decimals() external pure override returns (uint8) {
    return _decimals;
  }

  function symbol() external pure override returns (string memory) {
    return _symbol;
  }

  function name() external pure override returns (string memory) {
    return _name;
  }

  function getOwner() external view override returns (address) {
    return owner;
  }

  function balanceOf(address account) public view override returns (uint256) {
    return _balances[account];
  }

  function allowance(address holder, address spender) external view override returns (uint256) {
    return _allowances[holder][spender];
  }

  function approve(address spender, uint256 amount) public override returns (bool) {
    _allowances[msg.sender][spender] = amount;
    emit Approval(msg.sender, spender, amount);
    return true;
  }

  function approveMax(address spender) external returns (bool) {
    return approve(spender, _totalSupply);
  }

  function transfer(address recipient, uint256 amount) external override returns (bool) {
    return _transferFrom(msg.sender, recipient, amount);
  }

  function transferFrom(
    address sender,
    address recipient,
    uint256 amount
  ) external override returns (bool) {
    if (_allowances[sender][msg.sender] != _totalSupply) {
      _allowances[sender][msg.sender] = _allowances[sender][msg.sender].sub(amount, "Insufficient Allowance");
    }

    return _transferFrom(sender, recipient, amount);
  }

  function _transferFrom(
    address sender,
    address recipient,
    uint256 amount
  ) internal returns (bool) {
    if (inSwap) {
      return _basicTransfer(sender, recipient, amount);
    }

    // Avoid lauchpad buyers from ADD LP before launch
    if (!launched() && recipient == pair) {
      require(canAddLiquidityBeforeLaunch[sender]);
    }

    if (!authorizations[sender] && !authorizations[recipient]) {
      require(launched(), "Trading not open yet");
    }

    // max wallet check
    if (
      !authorizations[sender] &&
      recipient != address(this) &&
      recipient != address(DEAD) &&
      recipient != pair &&
      recipient != investmentFeeReceiver &&
      recipient != autoLiquidityReceiver
    ) {
      uint256 heldTokens = balanceOf(recipient);
      require((heldTokens + amount) <= _maxWallet, "Total Holding is currently limited, you can not buy that much.");
    }

    // max tx check
    checkTxLimit(sender, amount);

    // Set Fees
    if (sender == pair) {
      buyFees();
    } else if (recipient == pair) {
      sellFees();
    } else {
      transferFees();
    }

    //Exchange tokens
    if (shouldSwapBack() && totalFee > 0) {
      swapBack();
    }

    if (shouldAutoBuyback()) {
      triggerAutoBuyback();
    }

    _balances[sender] = _balances[sender].sub(amount, "Insufficient Balance");

    uint256 amountReceived = shouldTakeFee(sender) ? takeFee(recipient, amount) : amount;

    _balances[recipient] = _balances[recipient].add(amountReceived);

    // Dividend tracker
    if (!isDividendExempt[sender]) {
      try distributor.setShare(sender, balanceOf(sender)) {} catch {}
    }
    if (!isDividendExempt[recipient]) {
      try distributor.setShare(recipient, balanceOf(recipient)) {} catch {}
    }

    try distributor.process(distributorGas) {} catch {}

    emit Transfer(sender, recipient, amountReceived);
    return true;
  }

  function _basicTransfer(
    address sender,
    address recipient,
    uint256 amount
  ) internal returns (bool) {
    _balances[sender] = _balances[sender].sub(amount, "Insufficient Balance");
    _balances[recipient] = _balances[recipient].add(amount);
    emit Transfer(sender, recipient, amount);
    return true;
  }

  function checkTxLimit(address sender, uint256 amount) internal view {
    require(amount <= _maxTxAmount || isTxLimitExempt[sender], "TX Limit Exceeded");
  }

  // Internal Functions
  function buyFees() internal {
    liquidityFee = liquidityFeeBuy;
    buybackFee = buybackFeeBuy;
    reflectionFee = reflectionFeeBuy;
    investmentFee = investmentFeeBuy;
    totalFee = totalFeeBuy;
  }

  function sellFees() internal {
    liquidityFee = liquidityFeeSell;
    buybackFee = buybackFeeSell;
    reflectionFee = reflectionFeeSell;
    investmentFee = investmentFeeSell;
    totalFee = totalFeeSell;
  }

  function transferFees() internal {
    liquidityFee = liquidityFeeTransfer;
    buybackFee = buybackFeeTransfer;
    reflectionFee = reflectionFeeTransfer;
    investmentFee = investmentFeeTransfer;
    totalFee = totalFeeTransfer;
  }

  function shouldTakeFee(address sender) internal view returns (bool) {
    return !isFeeExempt[sender];
  }

  function takeFee(address sender, uint256 amount) internal returns (uint256) {
    uint256 feeAmount = amount.mul(totalFee).div(feeDenominator);

    _balances[address(this)] = _balances[address(this)].add(feeAmount);
    emit Transfer(sender, address(this), feeAmount);

    return amount.sub(feeAmount);
  }

  function shouldSwapBack() internal view returns (bool) {
    return msg.sender != pair && !inSwap && swapEnabled && _balances[address(this)] >= swapThreshold;
  }

  function swapBack() internal swapping {
    uint256 dynamicLiquidityFee = isOverLiquified(targetLiquidity, targetLiquidityDenominator) ? 0 : liquidityFee;
    uint256 amountToLiquify = swapThreshold.mul(dynamicLiquidityFee).div(totalFee).div(2);

    uint256 amountToSwap = swapThreshold.sub(amountToLiquify);

    address[] memory path = new address[](2);
    path[0] = address(this);
    path[1] = router.WETH();

    uint256 balanceBefore = address(this).balance;

    router.swapExactTokensForETHSupportingFeeOnTransferTokens(amountToSwap, 0, path, address(this), block.timestamp);

    uint256 amountETH = address(this).balance.sub(balanceBefore);

    uint256 totalETHFee = totalFee.sub(dynamicLiquidityFee.div(2));

    uint256 amountETHLiquidity = amountETH.mul(dynamicLiquidityFee).div(totalETHFee).div(2);
    uint256 amountETHReflection = amountETH.mul(reflectionFee).div(totalETHFee);
    uint256 amountETHInvestment = amountETH.mul(investmentFee).div(totalETHFee);

    try distributor.deposit{value: amountETHReflection}() {} catch {}
    payable(investmentFeeReceiver).transfer(amountETHInvestment);

    if (amountToLiquify > 0) {
      router.addLiquidityETH{value: amountETHLiquidity}(
        address(this),
        amountToLiquify,
        0,
        0,
        autoLiquidityReceiver,
        block.timestamp
      );
      emit AutoLiquify(amountETHLiquidity, amountToLiquify);
    }
  }

  // BuyBack functions
  function shouldAutoBuyback() internal view returns (bool) {
    return
      msg.sender != pair &&
      !inSwap &&
      autoBuybackEnabled &&
      autoBuybackBlockLast + autoBuybackBlockPeriod <= block.number && // After N blocks from last buyback
      address(this).balance >= autoBuybackAmount;
  }

  function triggerAutoBuyback() internal {
    buyTokens(autoBuybackAmount, DEAD);
    autoBuybackBlockLast = block.number;
    autoBuybackAccumulator = autoBuybackAccumulator.add(autoBuybackAmount);
    if (autoBuybackAccumulator > autoBuybackCap) {
      autoBuybackEnabled = false;
    }
  }

  function triggerZeusBuyback(uint256 amount) external onlyOwner {
    buyTokens(amount, DEAD);
    autoBuybackBlockLast = block.number;
    autoBuybackAccumulator = autoBuybackAccumulator.add(autoBuybackAmount);
    if (autoBuybackAccumulator > autoBuybackCap) {
      autoBuybackEnabled = false;
    }
  }

  function buyTokens(uint256 amount, address to) internal swapping {
    address[] memory path = new address[](2);
    path[0] = router.WETH();
    path[1] = address(this);

    router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: amount}(0, path, to, block.timestamp);
  }

  function setAutoBuybackSettings(
    bool _enabled,
    uint256 _cap,
    uint256 _amount,
    uint256 _period
  ) external onlyOwner {
    autoBuybackEnabled = _enabled;
    autoBuybackCap = _cap;
    autoBuybackAccumulator = 0;
    autoBuybackAmount = _amount;
    autoBuybackBlockPeriod = _period;
    autoBuybackBlockLast = block.number;
  }

  // Add extra rewards to holders
  function deposit() external payable onlyOwner {
    try distributor.deposit{value: msg.value}() {} catch {}
  }

  // Process rewards distributions to holders
  function process() external onlyOwner {
    try distributor.process(distributorGas) {} catch {}
  }

  // Stuck Balances Functions
  function rescueToken(address tokenAddress, uint256 tokens) public onlyOwner returns (bool success) {
    return IERC20(tokenAddress).transfer(msg.sender, tokens);
  }

  function clearStuckBalance(uint256 amountPercentage) external onlyOwner {
    uint256 amountETH = address(this).balance;
    payable(investmentFeeReceiver).transfer((amountETH * amountPercentage) / 100);
  }

  function setSellFees(
    uint256 _liquidityFee,
    uint256 _buybackFee,
    uint256 _reflectionFee,
    uint256 _investmentFee
  ) external onlyOwner {
    liquidityFeeSell = _liquidityFee;
    buybackFeeSell = _buybackFee;
    reflectionFeeSell = _reflectionFee;
    investmentFeeSell = _investmentFee;
    totalFeeSell = _liquidityFee + (_buybackFee) + (_reflectionFee) + (_investmentFee);
    require(totalFeeSell <= 1000, "Total sell fees exceeds 10%");
  }

  function setBuyFees(
    uint256 _liquidityFee,
    uint256 _buybackFee,
    uint256 _reflectionFee,
    uint256 _investmentFee
  ) external onlyOwner {
    liquidityFeeBuy = _liquidityFee;
    buybackFeeBuy = _buybackFee;
    reflectionFeeBuy = _reflectionFee;
    investmentFeeBuy = _investmentFee;
    totalFeeBuy = _liquidityFee + (_buybackFee) + (_reflectionFee) + (_investmentFee);
    require(totalFeeBuy <= 1000, "Total buy fees exceeds 10%");
  }

  function setTransferFees(
    uint256 _liquidityFee,
    uint256 _buybackFee,
    uint256 _reflectionFee,
    uint256 _investmentFee
  ) external onlyOwner {
    liquidityFeeTransfer = _liquidityFee;
    buybackFeeTransfer = _buybackFee;
    reflectionFeeTransfer = _reflectionFee;
    investmentFeeTransfer = _investmentFee;
    totalFeeTransfer = _liquidityFee + (_buybackFee) + (_reflectionFee) + (_investmentFee);
    require(totalFeeTransfer <= 1000, "Total transfer fees exceeds 10%");
  }

  function setFeeReceivers(address _autoLiquidityReceiver, address _investmentFeeReceiver) external onlyOwner {
    autoLiquidityReceiver = _autoLiquidityReceiver;
    investmentFeeReceiver = _investmentFeeReceiver;
  }

  function launched() internal view returns (bool) {
    return launchedAt != 0;
  }

  function launch() public onlyOwner {
    require(launchedAt == 0, "Already launched boi");
    launchedAt = block.number;
    launchedAtTimestamp = block.timestamp;
  }

  function setMaxWallet(uint256 amount) external onlyOwner {
    require(amount >= _totalSupply / 1000);
    _maxWallet = amount;
  }

  function setTxLimit(uint256 amount) external onlyOwner {
    require(amount >= _totalSupply / 1000);
    _maxTxAmount = amount;
  }

  function setIsDividendExempt(address holder, bool exempt) external onlyOwner {
    require(holder != address(this) && holder != pair);
    isDividendExempt[holder] = exempt;
    if (exempt) {
      distributor.setShare(holder, 0);
    } else {
      distributor.setShare(holder, _balances[holder]);
    }
  }

  function setIsFeeExempt(address holder, bool exempt) external onlyOwner {
    isFeeExempt[holder] = exempt;
  }

  function setIsTxLimitExempt(address holder, bool exempt) external onlyOwner {
    isTxLimitExempt[holder] = exempt;
  }

  function setSwapBackSettings(bool _enabled, uint256 _amount) external onlyOwner {
    swapEnabled = _enabled;
    swapThreshold = _amount;
  }

  function setCanTransferBeforeLaunch(address holder, bool exempt) external onlyOwner {
    canAddLiquidityBeforeLaunch[holder] = exempt; //Presale Address will be added as Exempt
    isTxLimitExempt[holder] = exempt;
    isFeeExempt[holder] = exempt;
  }

  function setTargetLiquidity(uint256 _target, uint256 _denominator) external onlyOwner {
    targetLiquidity = _target;
    targetLiquidityDenominator = _denominator;
  }

  function setDistributionCriteria(uint256 _minPeriod, uint256 _minDistribution) external onlyOwner {
    distributor.setDistributionCriteria(_minPeriod, _minDistribution);
  }

  function setDistributorSettings(uint256 gas) external onlyOwner {
    require(gas < 900000);
    distributorGas = gas;
  }

  function getCirculatingSupply() public view returns (uint256) {
    return _totalSupply.sub(balanceOf(DEAD)).sub(balanceOf(ZERO));
  }

  function getLiquidityBacking(uint256 accuracy) public view returns (uint256) {
    return accuracy.mul(balanceOf(pair).mul(2)).div(getCirculatingSupply());
  }

  function isOverLiquified(uint256 target, uint256 accuracy) public view returns (bool) {
    return getLiquidityBacking(accuracy) > target;
  }

  event AutoLiquify(uint256 amountETH, uint256 amountMRLN);
}

