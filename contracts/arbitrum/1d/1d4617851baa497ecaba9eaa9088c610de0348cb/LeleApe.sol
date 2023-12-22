/*
 *      LeleApe (LAPE)
 *
 *
 *      Supply:    1,000,000
 *      Max tx:      150,000 (15.0%)
 *      Max Wallet:  150,000 (15.0%)
 *      Fees buy / sell :  10.0%
 *      2% LP
 *      6% Marketing
 *      2% Team
 *      + 3% fees on sell for LP
 * 
 *
*/


//SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

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
        // Solidity only automatically asserts when dividing by 0
        require(b > 0, errorMessage);
        uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold

        return c;
    }
}

/**
 * BEP20 standard interface.
 */
interface IBEP20 {
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
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}


/**
 * Allows for contract ownership along with multi-address authorization
 */
abstract contract Auth {
    address internal owner;
    mapping (address => bool) internal authorizations;

    constructor(address _owner) {
        owner = _owner;
        authorizations[_owner] = true;
    }

    /**
     * Function modifier to require caller to be contract owner
     */
    modifier onlyOwner() {
        require(isOwner(msg.sender), "!OWNER"); _;
    }

    /**
     * Function modifier to require caller to be authorized
     */
    modifier authorized() {
        require(isAuthorized(msg.sender), "!AUTHORIZED"); _;
    }

    /**
     * Authorize address. Owner only
     */
    function authorize(address _address) public onlyOwner {
        authorizations[_address] = true;
    }

    /**
     * Remove address' authorization. Owner only
     */
    function unauthorize(address _address) public onlyOwner {
        authorizations[_address] = false;
    }

    /**
     * Check if address is owner
     */
    function isOwner(address _account) public view returns (bool) {
        return _account == owner;
    }

    /**
     * Return address' authorization status
     */
    function isAuthorized(address _address) public view returns (bool) {
        return authorizations[_address];
    }

    /**
     * Transfer ownership to new address. Caller must be owner. Leaves old owner authorized
     */
    function transferOwnership(address payable _address) public onlyOwner {
        owner = _address;
        authorizations[_address] = true;
        emit OwnershipTransferred(_address);
    }

    event OwnershipTransferred(address owner);
}

interface IDEXFactory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

interface IDEXRouter {
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

contract LeleApe is IBEP20, Auth {
    using SafeMath for uint256;

    address WCOIN;
    address DEAD = 0x000000000000000000000000000000000000dEaD;
    address ZERO = 0x0000000000000000000000000000000000000000;
    // address routerAddress = 0x10ED43C718714eb63d5aA57B78B54704E256024E; // BSC

    string constant _name = "LeleApe";
    string constant _symbol = "LAPE";
    uint8 constant _decimals = 18;

    uint256 _totalSupply = 1 * 10**6 * 10**_decimals;           // 1 000 000 LAPE
    uint256 public _maxTxAmount = _totalSupply * 15 / 100;      // 1% max tx
    uint256 public _maxWalletSize = _totalSupply * 15 / 100;    // 2% max wallet
    uint256 public swapThreshold = _totalSupply / 1000 * 3;     // 0.3%
    uint256 public presaleSupply = 45 * 10**5 * 10**_decimals;  // 45%
    uint256 liquidityFee = 2;
    uint256 teamFee = 2;
    uint256 marketingFee = 6;
    uint256 additionalSellingFee = 3;
    uint256 totalFee;
    uint256 feeDenominator = 100;
    uint256 antiBotBlocks = 2;
    uint256 public launchedAt;
    uint8 public cooldownTimerInterval = 3;                  // 3 sec between two transactions
    uint16 public antiDumpCooldownTimerInterval = 1*30;      // When antiDump: 30 sec between two transactions 
    uint256 public antiDumpAmount = _totalSupply / 100 * 5;  // When antiDump: 5% (50 000) max transaction

    // for antiDump
    struct SellingLog {
      uint256 cooldownTimer;
      uint256 amountSinceCooldownStarted;
    }

    mapping (address => uint256) _balances;
    mapping (address => mapping (address => uint256)) _allowances;
    mapping (address => bool) isFeeExempt;
    mapping (address => bool) isTxLimitExempt;
    mapping (address => bool) isTimelockExempt;
    mapping (address => bool) isSellTxLimitExempt;
    mapping (address => bool) public isBlacklisted;
    mapping (address => uint) private cooldownTimer;
    mapping (address => SellingLog) private sellingLogs;

    address public vaultWallet;
    address private marketingWallet;
    address private autoLiquifyWallet;
    address private teamWallet;

    IDEXRouter public router;
    address public pair;

    bool public tradingEnabled = false;
    bool public swapAndLiquifyEnabled = true;
    bool public additionalSellingFeeEnabled = true;
    bool public cooldownEnabled = true;
    bool public antiDumpEnabled = true;
    bool public antiBotTaxEnabled = true;
    bool inSwap = false;


    modifier swapping() {
        require(!inSwap, "swapping : no reentrancy");
        inSwap = true;
        _;
        inSwap = false;
    }

    modifier canTrade(address _sender, address _recipient) {
        if (!isTxLimitExempt[_sender] && !isTxLimitExempt[_recipient]) {
            if (_recipient == pair || _sender == pair) {
                require(tradingEnabled, "LAPE: Trading locked");   
            }
        }
        _;
    }

    constructor () Auth(msg.sender) {
        address _owner = owner;
        _allowances[address(this)][address(router)] = type(uint256).max;

        marketingWallet = _owner;
        vaultWallet = _owner;
        teamWallet = _owner;
        autoLiquifyWallet = _owner;

        isFeeExempt[_owner] = true;
        isFeeExempt[address(this)] = true;
        isFeeExempt[marketingWallet] = true;
        isFeeExempt[teamWallet] = true;
        isFeeExempt[vaultWallet] = true;
        isTxLimitExempt[_owner] = true;
        isTxLimitExempt[marketingWallet] = true;
        isTxLimitExempt[teamWallet] = true;
        isTxLimitExempt[vaultWallet] = true;
        isTxLimitExempt[pair] = true;
        isTxLimitExempt[DEAD] = true;
        isTimelockExempt[_owner] = true;
        isTimelockExempt[DEAD] = true;
        isTimelockExempt[address(this)] = true;
        isSellTxLimitExempt[_owner] = true;
        isSellTxLimitExempt[address(this)] = true;

        totalFee = liquidityFee.add(teamFee).add(marketingFee);
        _balances[_owner] = _totalSupply;
        emit Transfer(address(0), _owner, _totalSupply);
    }

    receive() external payable { }

    function totalSupply() external view override returns (uint256) { return _totalSupply; }
    function decimals() external pure override returns (uint8) { return _decimals; }
    function symbol() external pure override returns (string memory) { return _symbol; }
    function name() external pure override returns (string memory) { return _name; }
    function getOwner() external view override returns (address) { return owner; }
    function balanceOf(address account) public view override returns (uint256) { return _balances[account]; }
    function allowance(address holder, address spender) external view override returns (uint256) { return _allowances[holder][spender]; }

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

    function _transferFrom(address sender, address recipient, uint256 amount) internal canTrade(sender, recipient) returns (bool) {
        if(inSwap){ return _basicTransfer(sender, recipient, amount); }

        require(!isBlacklisted[sender] && !isBlacklisted[recipient], "Sender or recipient is blacklisted.");
        
        if (!isTxLimitExempt[sender]) {
            require(amount <= _maxTxAmount, "TX Limit Exceeded");
        }

        if (recipient != pair && recipient != DEAD) {
            require(isTxLimitExempt[recipient] || _balances[recipient] + amount <= _maxWalletSize, "Transfer amount exceeds the bag size.");
        }

        if (sender == pair &&
            cooldownEnabled &&
            !isTimelockExempt[recipient]) {
            require(cooldownTimer[recipient] < block.timestamp, "Please wait for 1min between two operations");
            cooldownTimer[recipient] = block.timestamp + cooldownTimerInterval;
        }

        if (recipient == pair &&
            antiDumpEnabled &&
            !isSellTxLimitExempt[sender]) {
            require(amount <= antiDumpAmount, "antiDump activated - Max Sell Tx is 2 000 000 / 10min");
            if (sellingLogs[sender].cooldownTimer >= block.timestamp) {
                require(sellingLogs[sender].amountSinceCooldownStarted + amount <= antiDumpAmount, "antiDump - Sell Limit Exceeded (2 000 000 / 10 min)");
                sellingLogs[sender].amountSinceCooldownStarted = sellingLogs[sender].amountSinceCooldownStarted + amount;
            }
            if (sellingLogs[sender].cooldownTimer < block.timestamp) {
                sellingLogs[sender].cooldownTimer = block.timestamp + antiDumpCooldownTimerInterval;
                sellingLogs[sender].amountSinceCooldownStarted = amount;
            }
        }

        if(shouldSwapBack()){ swapBack(); }

        if(!launched() && recipient == pair){ require(_balances[sender] > 0); launch(); }

        _balances[sender] = _balances[sender].sub(amount, "Insufficient Balance");

        uint256 amountReceived = shouldTakeFee(sender) ? takeFee(sender, recipient, amount) : amount;
        _balances[recipient] = _balances[recipient].add(amountReceived);

        emit Transfer(sender, recipient, amountReceived);
        return true;
    }
    
    function _basicTransfer(address sender, address recipient, uint256 amount) internal returns (bool) {
        _balances[sender] = _balances[sender].sub(amount, "Insufficient Balance");
        _balances[recipient] = _balances[recipient].add(amount);
        emit Transfer(sender, recipient, amount);
        return true;
    }
    
    function shouldTakeFee(address sender) internal view returns (bool) {
        return !isFeeExempt[sender];
    }

    function getTotalFee(bool selling) internal view returns (uint256) {
        if((launchedAt + antiBotBlocks >= block.number) || antiBotTaxEnabled){ return feeDenominator.sub(11); }
        if(selling && additionalSellingFeeEnabled) { return totalFee.add(additionalSellingFee); }
        return totalFee;
    }

    function takeFee(address sender, address receiver, uint256 amount) internal returns (uint256) {
        uint256 feeAmount = amount.mul(getTotalFee(receiver == pair)).div(feeDenominator);

        _balances[address(this)] = _balances[address(this)].add(feeAmount);
        emit Transfer(sender, address(this), feeAmount);

        return amount.sub(feeAmount);
    }

    function shouldSwapBack() internal view returns (bool) {
        return msg.sender != pair
        && !inSwap
        && swapAndLiquifyEnabled
        && _balances[address(this)] >= swapThreshold;
    }

    function swapBack() internal swapping {
        uint256 contractTokenBalance = balanceOf(address(this));
        uint256 amountToLiquify = contractTokenBalance.mul(liquidityFee).div(totalFee).div(2);
        uint256 amountToSwap = contractTokenBalance.sub(amountToLiquify);

        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = WCOIN;

        uint256 balanceBefore = address(this).balance;

        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            amountToSwap,
            0,
            path,
            address(this),
            block.timestamp
        );
        uint256 amountBNB = address(this).balance.sub(balanceBefore);
        uint256 totalBNBFee = totalFee.sub(liquidityFee.div(2));
        uint256 amountBNBLiquidity = amountBNB.mul(liquidityFee).div(totalBNBFee).div(2);

        // send marketingAmount
        uint256 amountBNBToTransfer = amountBNB.mul(marketingFee).div(totalBNBFee);
        (bool marketingSuccess, /* bytes memory data */) = payable(marketingWallet).call{value: amountBNBToTransfer, gas: 30000}("");
        require(marketingSuccess, "marketingWallet rejected ETH transfer");
        // send teamAmount
        amountBNBToTransfer = amountBNB.mul(teamFee).div(totalBNBFee);
        (bool teamSuccess, /* bytes memory data */) = payable(teamWallet).call{value: amountBNBToTransfer, gas: 30000}("");
        require(teamSuccess, "teamWallet rejected ETH transfer");

        if(amountToLiquify > 0){
            router.addLiquidityETH{value: amountBNBLiquidity}(
                address(this),
                amountToLiquify,
                0,
                0,
                autoLiquifyWallet,
                block.timestamp
            );
            emit AutoLiquify(amountBNBLiquidity, amountToLiquify);
        }
    }

    function launched() internal view returns (bool) {
        return launchedAt != 0;
    }

    function launch() internal {
        launchedAt = block.number;
    }

    function setTxLimit(uint256 amount) external authorized {
        require(amount >= _totalSupply / 1000);
        _maxTxAmount = amount * (10 ** _decimals);
    }

   function setMaxWallet(uint256 amount) external authorized {
        require(amount >= _totalSupply / 1000 );
        _maxWalletSize = amount * (10 ** _decimals);
    }    

    function setFeeExempt(address _address, bool _bool) external authorized {
        require(isFeeExempt[_address] != _bool, "This address already has this FeeExempt value");
        isFeeExempt[_address] = _bool;
    }

    function setTxLimitExempt(address _address, bool _bool) external authorized {
        require(isTxLimitExempt[_address] != _bool, "This address already has this TxLimitExempt value");
        isTxLimitExempt[_address] = _bool;
    }

    function setTimelockExempt(address _address, bool _bool) external authorized {
        require(isTimelockExempt[_address] != _bool, "This address already has this TimelockExempt value");
        isTimelockExempt[_address] = _bool;
    }

    function setSellTxLimitExempt(address _address, bool _bool) external authorized {
        require(isSellTxLimitExempt[_address] != _bool, "This address already has this SellTxLimitExempt value");
        isSellTxLimitExempt[_address] = _bool;
    }

    function setAllExempt(address _address) public authorized {
        isFeeExempt[_address] = true;
        isTxLimitExempt[_address] = true;
        isTimelockExempt[_address] = true;
        isSellTxLimitExempt[_address] = true;
    }

    function setTeamMember(address _address) external onlyOwner {
      setAllExempt(_address);
      authorize(_address);
    }

    function setFees(uint256 _liquidityFee, uint256 _teamFee, uint256 _marketingFee, uint256 _additionalSellingFee, uint256 _feeDenominator) external authorized {
        liquidityFee = _liquidityFee;
        teamFee = _teamFee;
        marketingFee = _marketingFee;
        totalFee = _liquidityFee.add(_teamFee).add(_marketingFee);
        additionalSellingFee = _additionalSellingFee;
        feeDenominator = _feeDenominator;
    }

    function setReceivers(address _marketingWallet, address _teamWallet, address _vaultWallet, address _autoLiquifyWallet) external authorized {
        marketingWallet = _marketingWallet;
        teamWallet = _teamWallet;
        vaultWallet = _vaultWallet;
        autoLiquifyWallet = _autoLiquifyWallet;
        isFeeExempt[_marketingWallet] = true;
        isFeeExempt[_teamWallet] = true;
        isFeeExempt[_vaultWallet] = true;
        isFeeExempt[_autoLiquifyWallet] = true;
    }

    function setSwapBackSettings(bool _enabled, uint256 _amount) external authorized {
        swapAndLiquifyEnabled = _enabled;
        swapThreshold = _amount;
    }

    function transferContractBalance() external authorized {
        uint256 contractETHBalance = address(this).balance;
        payable(marketingWallet).transfer(contractETHBalance);
    }

    function transferForeignToken(address _token) public authorized {
        require(_token != address(this), "Can't let you take all native token");
        uint256 _contractBalance = IBEP20(_token).balanceOf(address(this));
        payable(marketingWallet).transfer(_contractBalance);
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

    function setAdditionalSellingFeeEnabled(bool _bool) external authorized {
        require(additionalSellingFeeEnabled != _bool, "additionalSellingFeeEnabled already has this value");
        additionalSellingFeeEnabled = _bool;
    }

    function setTradingEnabled(bool _bool) external authorized {
        require(tradingEnabled != _bool, "tradingEnabled already has this value");
        tradingEnabled = _bool;
    }

    function setAntiBotTaxEnabled(bool _bool) external authorized {
        require(antiBotTaxEnabled != _bool, "antiBotTaxEnabled already has this value");
        antiBotTaxEnabled = _bool;
    }

    function setBlacklisted(address _address, bool _bool) external authorized {
        require(isBlacklisted[_address] != _bool, "This address already has this value");
        isBlacklisted[_address] = _bool;
    }

    function setCooldownEnabled(bool _bool) public authorized {
        cooldownEnabled = _bool;
    }

    function setCooldownTimerInterval(uint8 _interval) public authorized {
        cooldownTimerInterval = _interval;
    }

    function setAntiDumpEnabled(bool _bool) public authorized {
        require(antiDumpEnabled != _bool, "antiDumpEnabled has already this value");
        antiDumpEnabled = _bool;
    }

    function setAntiDumpSettings(uint8 _interval, uint256 _amount) public authorized {
        antiDumpCooldownTimerInterval = _interval;
        antiDumpAmount = _amount * (10 ** _decimals);
    }

    function burn(uint256 amount) public {
        require(amount > 0, "Amount to burn must be greater than 0");
        require(msg.sender != address(0), "Burn not possible from the zero address");
        _balances[msg.sender] = _balances[msg.sender].sub(amount, "Burn amount exceeds balance");
        _totalSupply = _totalSupply.sub(amount);
        emit Transfer(msg.sender, DEAD, amount);
    }
    
    event AutoLiquify(uint256 amountBNB, uint256 amountBOG);
}