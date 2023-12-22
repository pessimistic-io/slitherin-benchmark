/*
Test

*/

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

library SafeMathInt {
    int256 private constant MIN_INT256 = int256(1) << 255;
    int256 private constant MAX_INT256 = ~(int256(1) << 255);

    function mul(int256 a, int256 b) internal pure returns (int256) {
        int256 c = a * b;

        require(c != MIN_INT256 || (a & MIN_INT256) != (b & MIN_INT256));
        require((b == 0) || (c / b == a));
        return c;
    }

    function div(int256 a, int256 b) internal pure returns (int256) {
        require(b != -1 || a != MIN_INT256);

        return a / b;
    }

    function sub(int256 a, int256 b) internal pure returns (int256) {
        int256 c = a - b;
        require((b >= 0 && c <= a) || (b < 0 && c > a));
        return c;
    }

    function add(int256 a, int256 b) internal pure returns (int256) {
        int256 c = a + b;
        require((b >= 0 && c >= a) || (b < 0 && c < a));
        return c;
    }

    function abs(int256 a) internal pure returns (int256) {
        require(a != MIN_INT256);
        return a < 0 ? -a : a;
    }
}

library SafeMath {
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");

        return c;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return sub(a, b, "SafeMath: subtraction overflow");
    }

    function sub(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
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

    function div(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        require(b > 0, errorMessage);
        uint256 c = a / b;

        return c;
    }

    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b != 0);
        return a % b;
    }
}

interface IERC20 {
    function totalSupply() external view returns (uint256);

    function balanceOf(address who) external view returns (uint256);

    function allowance(address owner, address spender)
    external
    view
    returns (uint256);

    function transfer(address to, uint256 value) external returns (bool);

    function approve(address spender, uint256 value) external returns (bool);

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);

    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
}

interface IPancakeSwapPair {
    event Approval(address indexed owner, address indexed spender, uint value);
    event Transfer(address indexed from, address indexed to, uint value);

    function name() external pure returns (string memory);
    function symbol() external pure returns (string memory);
    function decimals() external pure returns (uint8);
    function totalSupply() external view returns (uint);
    function balanceOf(address owner) external view returns (uint);
    function allowance(address owner, address spender) external view returns (uint);

    function approve(address spender, uint value) external returns (bool);
    function transfer(address to, uint value) external returns (bool);
    function transferFrom(address from, address to, uint value) external returns (bool);

    function DOMAIN_SEPARATOR() external view returns (bytes32);
    function PERMIT_TYPEHASH() external pure returns (bytes32);
    function nonces(address owner) external view returns (uint);

    function permit(address owner, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s) external;

    event Mint(address indexed sender, uint amount0, uint amount1);
    event Burn(address indexed sender, uint amount0, uint amount1, address indexed to);
    event Swap(
        address indexed sender,
        uint amount0In,
        uint amount1In,
        uint amount0Out,
        uint amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);

    function MINIMUM_LIQUIDITY() external pure returns (uint);
    function factory() external view returns (address);
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function price0CumulativeLast() external view returns (uint);
    function price1CumulativeLast() external view returns (uint);
    function kLast() external view returns (uint);

    function mint(address to) external returns (uint liquidity);
    function burn(address to) external returns (uint amount0, uint amount1);
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external;
    function skim(address to) external;
    function sync() external;

    function initialize(address, address) external;
}

interface IPancakeSwapRouter{
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
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB);
    function removeLiquidityETH(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external returns (uint amountToken, uint amountETH);
    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint amountA, uint amountB);
    function removeLiquidityETHWithPermit(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint amountToken, uint amountETH);
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
    function swapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
    function swapExactETHForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline)
    external
    payable
    returns (uint[] memory amounts);
    function swapTokensForExactETH(uint amountOut, uint amountInMax, address[] calldata path, address to, uint deadline)
    external
    returns (uint[] memory amounts);
    function swapExactTokensForETH(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline)
    external
    returns (uint[] memory amounts);
    function swapETHForExactTokens(uint amountOut, address[] calldata path, address to, uint deadline)
    external
    payable
    returns (uint[] memory amounts);

    function quote(uint amountA, uint reserveA, uint reserveB) external pure returns (uint amountB);
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) external pure returns (uint amountOut);
    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) external pure returns (uint amountIn);
    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);
    function getAmountsIn(uint amountOut, address[] calldata path) external view returns (uint[] memory amounts);
    function removeLiquidityETHSupportingFeeOnTransferTokens(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external returns (uint amountETH);
    function removeLiquidityETHWithPermitSupportingFeeOnTransferTokens(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint amountETH);

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

interface IPancakeSwapFactory {
    event PairCreated(address indexed token0, address indexed token1, address pair, uint);

    function feeTo() external view returns (address);
    function feeToSetter() external view returns (address);

    function getPair(address tokenA, address tokenB) external view returns (address pair);
    function allPairs(uint) external view returns (address pair);
    function allPairsLength() external view returns (uint);

    function createPair(address tokenA, address tokenB) external returns (address pair);

    function setFeeTo(address) external;
    function setFeeToSetter(address) external;
}



contract Ownable {
    address private _owner;

    event OwnershipRenounced(address indexed previousOwner);

    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    constructor() {
        _owner = msg.sender;
    }

    function owner() public view returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(isOwner());
        _;
    }

    function isOwner() public view returns (bool) {
        return msg.sender == _owner;
    }

    function renounceOwnership() public onlyOwner {
        emit OwnershipRenounced(_owner);
        _owner = address(0);
    }

    function transferOwnership(address newOwner) public onlyOwner {
        _transferOwnership(newOwner);
    }

    function _transferOwnership(address newOwner) internal {
        require(newOwner != address(0));
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

abstract contract ERC20Detailed is IERC20 {
    string private _name;
    string private _symbol;
    uint8 private _decimals;

    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_
    ) {
        _name = name_;
        _symbol = symbol_;
        _decimals = decimals_;
    }

    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function decimals() public view returns (uint8) {
        return _decimals;
    }
}

contract Test is ERC20Detailed, Ownable {

    using SafeMath for uint256;
    using SafeMathInt for int256;



    string public _name = "Test";
    string public _symbol = "$TEST";
    uint256 public _decimals = 9;

    IPancakeSwapPair public pairContract;
    
    address[] public _markerPairs;
    uint256 public _markerPairCount;
    mapping(address => bool) _isFeeExempt;
    mapping(address => bool)  _isExcludedFromMaxWallet;
    mapping(address => bool) public automatedMarketMakerPairs;

    modifier validRecipient(address to) {
        require(to != address(0x0));
        _;
    }

    uint256 public constant DECIMALS = 9;
    uint256 public constant MAX_UINT256 = ~uint256(0);
    uint256 public constant RATE_DECIMALS = 9;

    uint256 private constant INITIAL_FRAGMENTS_SUPPLY = 10 * 10**8 * 10**DECIMALS;
//split liq to 2
    uint256 public liquidityFee = 10;
    uint256 public liquidityFee2 = 10;
    uint256 public treasuryFee = 20;
    uint256 public competitionFee = 20;

    uint256 public sellFee = competitionFee;
    uint256 public burnFee = 40;
    uint256 public totalFee = liquidityFee.add(liquidityFee2).add(treasuryFee).add(burnFee);
    uint256 public feeDenominator = 1000;

    address DEAD = 0x000000000000000000000000000000000000dEaD;
    address ZERO = 0x0000000000000000000000000000000000000000;

    address public competitionReceiver;

    address public lpReceiver;
    address public treasuryReceiver;
    address public firePit;
    address public pairAddress;
    bool public swapEnabled = true;
    IPancakeSwapRouter public router;
    address public pair;
    bool inSwap = false;
    modifier swapping() {
        inSwap = true;
        _;
        inSwap = false;
    }

    uint256 private constant TOTAL_GONS = MAX_UINT256 - (MAX_UINT256 % INITIAL_FRAGMENTS_SUPPLY);
    uint256 private constant MAX_SUPPLY = 10 * 10**10 * 10**DECIMALS;

    // BOOL Variables
    bool public _autoRebase = true;
    bool public _autoAddLiquidity = false;
    bool public maxWalletActive = false;
    bool public antiSnipeON = false;


    // INT Variables
    uint256 public _initRebaseStartTime;
    uint256 public _lastRebasedTime;
    uint256 public _lastAddLiquidityTime;
    uint256 public _totalSupply;
    uint256 private _gonsPerFragment;

    uint256 public maxTxAmountBuy;
    uint256 public maxTxAmountSell;
    uint256 public maxWalletAmount;
    uint256 public SellLimit = 5;

    struct user {
        uint256 lastTradeTime;
        uint256 tradeAmount;
    }

    uint256 public TwentyFourhours = 86400;

    mapping(address => user) public tradeData;
    
   
    // MAPPING
    mapping(address => uint256) private _gonBalances;
    mapping(address => mapping(address => uint256)) private _allowedFragments;
    mapping(address => bool) public blacklist;

    // EVENT
    event Rebased(uint256 indexed epoch, uint256 totalSupply);

    constructor() ERC20Detailed("Test", "$Test", uint8(DECIMALS)) Ownable() {

        router = IPancakeSwapRouter(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506);
        pair = IPancakeSwapFactory(router.factory()).createPair(
            address(this),
            router.WETH()
            
        );

        lpReceiver = 0x5216a108466DDaae3C186dFbEc4ad830D04DD940;
        treasuryReceiver = 0xa35181B893a4404D4D984a121F60Ca8b744B5870;
        competitionReceiver = 0xE838b5bc0982f8E9638eE9D90503c5BD4b8b0669;
        firePit = 0x000000000000000000000000000000000000dEaD;

        _allowedFragments[address(this)][address(router)] = type(uint256).max;
        pairAddress = pair;
        pairContract = IPancakeSwapPair(pair);

        setAutomatedMarketMakerPair(pair, true);
        _totalSupply = INITIAL_FRAGMENTS_SUPPLY;
        _gonBalances[owner()] = TOTAL_GONS;
        _gonsPerFragment = TOTAL_GONS.div(_totalSupply);
        _initRebaseStartTime = block.timestamp;
        _lastRebasedTime = block.number;


        _isFeeExempt[owner()] = true;
        _isFeeExempt[address(this)] = true;

        _isExcludedFromMaxWallet[owner()] = true;
        _isExcludedFromMaxWallet[address(this)] = true;
        _isExcludedFromMaxWallet[address(firePit)] = true;

        maxTxAmountBuy = INITIAL_FRAGMENTS_SUPPLY / 50;
        maxTxAmountSell = INITIAL_FRAGMENTS_SUPPLY / 25;
        maxWalletAmount = INITIAL_FRAGMENTS_SUPPLY / 50;




        emit Transfer(address(0x0),  owner(), _totalSupply);
    }

    function setFees(               
        uint256 _liquidityFee,
        uint256 _liquidityFee2,
        uint256 _treasuryFee,
        uint256 _competitionFee,
        uint256 _burnFee
    ) external onlyOwner {
        liquidityFee = _liquidityFee;
        liquidityFee2 = _liquidityFee2;
        treasuryFee = _treasuryFee;
        competitionFee = _competitionFee;
        burnFee = _burnFee;

        sellFee = competitionFee;
        totalFee = liquidityFee.add(liquidityFee2).add(treasuryFee).add(burnFee);

    }
    function markerPairAddress(uint256 value) public view returns (address) {
        return _markerPairs[value];
    }
    function setMaxTransactionAmount(
        uint256 _maxTxAmountBuyPct,
        uint256 _maxTxAmountSellPct
    ) external onlyOwner {
        maxTxAmountBuy = _totalSupply / _maxTxAmountBuyPct; // 100 = 1%, 50 = 2% etc. The number you input in BSCScan is the divider
        maxTxAmountSell = _totalSupply / _maxTxAmountSellPct; // 100 = 1%, 50 = 2% etc. so 50 = 2%, 20 = 5%
    }
    
    function setMaxWalletAmount(uint256 _maxWalletAmountPct) external onlyOwner {
        maxWalletAmount = _totalSupply / _maxWalletAmountPct; // 100 = 1%, 50 = 2% etc.
      
    }

    function excludeFromMaxWallet(address account, bool excluded) 
        external
        onlyOwner
    {
        require(
            _isExcludedFromMaxWallet[account] != excluded,
            "_isExcludedFromMaxWallet already set to that value"
        );
        _isExcludedFromMaxWallet[account] = excluded;

       
    }

    function manualRebase() external onlyOwner {
        rebase();
    }

    function rebase() internal {

        if ( inSwap ) return;

        uint deno = 10**7 * 10**18;             
        uint rebaseRate = 347 * 10**18;       //858
        uint minuteRebaseRate = 6945 * 10**18;   //17161
        uint hourRebaseRate = 416666 * 10**18; //1030130
        uint dayRebaseRate = 10000000 * 10**18; //25018221
        uint blockCount = block.number.sub(_lastRebasedTime);
        uint tmp = _totalSupply;
        for (uint idx = 0; idx < blockCount.mod(20); idx++) { // 3 sec rebase
            // S' = S(1+p)^r
            tmp = tmp.mul(deno.mul(100).add(rebaseRate)).div(deno.mul(100));
        }

        for (uint idx = 0; idx < blockCount.div(20).mod(60); idx++) { // 1 min rebase
            // S' = S(1+p)^r
            tmp = tmp.mul(deno.mul(100).add(minuteRebaseRate)).div(deno.mul(100));
        }

        for (uint idx = 0; idx < blockCount.div(20 * 60).mod(24); idx++) { // 1 hour rebase
            // S' = S(1+p)^r
            tmp = tmp.mul(deno.mul(100).add(hourRebaseRate)).div(deno.mul(100));
        }

        for (uint idx = 0; idx < blockCount.div(20 * 60 * 24); idx++) { // 1 day rebase
            // S' = S(1+p)^r
            tmp = tmp.mul(deno.mul(100).add(dayRebaseRate)).div(deno.mul(100));
        }

        _totalSupply = tmp;
        _gonsPerFragment = TOTAL_GONS.div(tmp);
        _lastRebasedTime = block.number;

        pairContract.sync();

        emit Rebased(block.timestamp, _totalSupply);
    }

    function transfer(address to, uint256 value)
    external
    override
    validRecipient(to)
    returns (bool)
    {
        _transferFrom(msg.sender, to, value);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external override validRecipient(to) returns (bool) {

        if (_allowedFragments[from][msg.sender] != type(uint256).max) {
            _allowedFragments[from][msg.sender] = _allowedFragments[from][
            msg.sender
            ].sub(value, "Insufficient Allowance");
        }
        _transferFrom(from, to, value);
        return true;
    }

    function _basicTransfer(
        address from,
        address to,
        uint256 amount
    ) internal returns (bool) {
        uint256 gonAmount = amount.mul(_gonsPerFragment);
        _gonBalances[from] = _gonBalances[from].sub(gonAmount);
        _gonBalances[to] = _gonBalances[to].add(gonAmount);
        return true;
    }
 
    function balanceOf(address who) public view override returns (uint256) {
        return _gonBalances[who].div(_gonsPerFragment);
    }
    function _transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) internal returns (bool) {
        bool excludedAccount = _isFeeExempt[sender] || _isFeeExempt[recipient]; //added
        require(!blacklist[sender] && !blacklist[recipient], "in_blacklist");
        if (automatedMarketMakerPairs[recipient] && !excludedAccount) {  //experimental sell limits
            require(amount <= maxTxAmountSell, "Exceeded max sell limit");
                    uint blkTime = block.timestamp;
          
                        uint256 onePercent = balanceOf(sender).mul(SellLimit).div(100); //Should use variable
                        require(amount <= onePercent, "ERR: Can't sell more than set %");
            
                        if( blkTime > tradeData[sender].lastTradeTime + TwentyFourhours) {
                        tradeData[sender].lastTradeTime = blkTime;
                        tradeData[sender].tradeAmount = amount;
                        }
                            else if( (blkTime < tradeData[sender].lastTradeTime + TwentyFourhours) && (( blkTime > tradeData[sender].lastTradeTime)) ){
                            require(tradeData[sender].tradeAmount + amount <= onePercent, "ERR: Can't sell more than 1% in One day");
                            tradeData[sender].tradeAmount = tradeData[sender].tradeAmount + amount;
                        }







        }

        if (maxWalletActive && automatedMarketMakerPairs[sender] && !excludedAccount) {
            require(amount <= maxTxAmountBuy, "Exceeded max buy limit");
            require(balanceOf(recipient).add(amount) <= maxWalletAmount,
            "Recipient cannot hold more than maxWalletAmount");
        }

        if(antiSnipeON && automatedMarketMakerPairs[sender]){
                    blacklist[recipient] = true;
                }

        if (inSwap) {
            return _basicTransfer(sender, recipient, amount);
        }
        if (shouldRebase()) {
            rebase();
        }

    
        if (shouldSwapBack()) {
            swapBack();
        }

        uint256 gonAmount = amount.mul(_gonsPerFragment);
        _gonBalances[sender] = _gonBalances[sender].sub(gonAmount);
        uint256 gonAmountReceived = shouldTakeFee(sender, recipient)
        ? takeFee(sender, recipient, gonAmount)
        : gonAmount;
        _gonBalances[recipient] = _gonBalances[recipient].add(
            gonAmountReceived
        );


        emit Transfer(
            sender,
            recipient,
            gonAmountReceived.div(_gonsPerFragment)
        );
        return true;
    }

    function calculateAmount(uint256 amount, uint256 numerator, uint256 denumerator) internal pure returns (uint256){
        return amount.mul(numerator).div(denumerator);
    }

    function set_antiSnipeON(bool on) public onlyOwner{
        antiSnipeON = on;
    }


    function set_MaxBuyActives(bool _maxWallet) public onlyOwner{
        maxWalletActive = _maxWallet;
      
        
    }
    function setAutomatedMarketMakerPair(address _pair, bool _bool) public onlyOwner {
        automatedMarketMakerPairs[_pair] = _bool;

        if (_bool) {
            _markerPairs.push(_pair);
            _markerPairCount++;
        } else {
            require(_markerPairs.length > 1, "Require more than 1 marketPair");
            for (uint256 i = 0; i < _markerPairs.length; i++) {
                if (_markerPairs[i] == _pair) {
                    _markerPairs[i] = _markerPairs[_markerPairs.length - 1];
                    _markerPairs.pop();
                    break;
                }
            }
        }

        
    }

    function takeFee(   
        address sender,
        address recipient,
        uint256 gonAmount
    ) internal  returns (uint256) {
        uint256 _totalFee = totalFee;
        if(antiSnipeON){
            _totalFee = 900;
          
        }

        uint256 _burnFee = 0;
        uint256 _liquidityFee = 0;
        if (recipient == pair) {
            _totalFee = totalFee.add(sellFee);
        }
        _burnFee = calculateAmount(gonAmount, burnFee, feeDenominator);
        _liquidityFee = calculateAmount(gonAmount, liquidityFee, feeDenominator);
        uint256 feeAmount = gonAmount.div(feeDenominator).mul(_totalFee);

      /*  if(_burnFee > 0){
            _gonBalances[firePit] = _gonBalances[firePit].add(_burnFee);
            emit Transfer(sender, firePit, _burnFee.div(_gonsPerFragment));
        }
      */
        if(_burnFee > 0){
            _totalSupply = _totalSupply.sub(_burnFee);
        }   


        if(_liquidityFee > 0){
            _gonBalances[lpReceiver] = _gonBalances[lpReceiver].add(_liquidityFee);
            emit Transfer(sender, lpReceiver, _liquidityFee.div(_gonsPerFragment));
        }
      
        uint256 maintainFee = _totalFee - burnFee - liquidityFee;

        _gonBalances[address(this)] = _gonBalances[address(this)].add(
            gonAmount.div(feeDenominator).mul(maintainFee)
        );
      

        emit Transfer(sender, address(this), feeAmount.div(_gonsPerFragment));
        return gonAmount.sub(feeAmount);
    }
  
    function swapBack() internal swapping {

        uint256 amountToSwap = _gonBalances[address(this)].div(_gonsPerFragment);

        if( amountToSwap == 0) {
            return;
        }

        uint256 balanceBefore = address(this).balance;
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = router.WETH();


        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            amountToSwap,
            0,
            path,
            address(this),
            block.timestamp
        );

        uint256 currentBalance = address(this).balance.sub(
            balanceBefore
        );

        uint256 _currentFee = treasuryFee.add(competitionFee).add(liquidityFee2);

        (bool success, ) = payable(treasuryReceiver).call{
        value: currentBalance.mul(treasuryFee).div(
            _currentFee
        ),
        gas: 30000
        }("");

        (success, ) = payable(competitionReceiver).call{
        value: currentBalance.mul(competitionFee).div(
            _currentFee
        ),
        gas: 30000
        }("");

        (success, ) = payable(lpReceiver).call{
        value: currentBalance.mul(liquidityFee2).div(
            _currentFee
        ),
        gas: 30000
        }("");
        
    }

    function withdrawAllToTreasury() external swapping onlyOwner {

        uint256 amountToSwap = _gonBalances[address(this)].div(_gonsPerFragment);
        require( amountToSwap > 0,"There is no token deposited in token contract");
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = router.WETH();
        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            amountToSwap,
            0,
            path,
            treasuryReceiver,
            block.timestamp
        );
    }


    function rescueToken(address tokenAddress, address to) external onlyOwner returns (bool success) {
        uint256 _contractBalance = IERC20(tokenAddress).balanceOf(address(this));

      
        return IERC20(tokenAddress).transfer(to, _contractBalance);
    }

    function rescueBNB(uint256 amount) external onlyOwner{
    payable(msg.sender).transfer(amount);
    }

    function shouldTakeFee(address from, address to)
    internal
    view
    returns (bool)
    {
        return
        (pair == from || pair == to) &&
        !_isFeeExempt[from];
    }

    function shouldRebase() internal view returns (bool) {
        return
        _autoRebase &&
        (_totalSupply < MAX_SUPPLY) &&
        msg.sender != pair  &&
        !inSwap &&
        block.number >= (_lastRebasedTime + 1);
    }

    
    function shouldSwapBack() internal view returns (bool) {
        return
        !inSwap &&
        msg.sender != pair  ;
    }

    function setAutoRebase(bool _flag) external onlyOwner {
        if (_flag) {
            _autoRebase = _flag;
            _lastRebasedTime = block.number;
        } else {
            _autoRebase = _flag;
        }
    }

    function setAutoAddLiquidity(bool _flag) external onlyOwner {
        if(_flag) {
            _autoAddLiquidity = _flag;
            _lastAddLiquidityTime = block.timestamp;
        } else {
            _autoAddLiquidity = _flag;
        }
    }

    function allowance(address owner_, address spender)
    external
    view
    override
    returns (uint256)
    {
        return _allowedFragments[owner_][spender];
    }

    function decreaseAllowance(address spender, uint256 subtractedValue)
    external
    returns (bool)
    {
        uint256 oldValue = _allowedFragments[msg.sender][spender];
        if (subtractedValue >= oldValue) {
            _allowedFragments[msg.sender][spender] = 0;
        } else {
            _allowedFragments[msg.sender][spender] = oldValue.sub(
                subtractedValue
            );
        }
        emit Approval(
            msg.sender,
            spender,
            _allowedFragments[msg.sender][spender]
        );
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue)
    external
    returns (bool)
    {
        _allowedFragments[msg.sender][spender] = _allowedFragments[msg.sender][
        spender
        ].add(addedValue);
        emit Approval(
            msg.sender,
            spender,
            _allowedFragments[msg.sender][spender]
        );
        return true;
    }

    function approve(address spender, uint256 value)
    external
    override
    returns (bool)
    {
        _allowedFragments[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function checkFeeExempt(address _addr) external view returns (bool) {
        return _isFeeExempt[_addr];
    }

    function getCirculatingSupply() public view returns (uint256) {
        return
        (TOTAL_GONS.sub(_gonBalances[DEAD]).sub(_gonBalances[ZERO])).div(
            _gonsPerFragment
        );
    }

    function isNotInSwap() external view returns (bool) {
        return !inSwap;
    }

    function manualSync() external {
        IPancakeSwapPair(pair).sync();
    }


    function setFeeReceivers(
        address _lpReceiver,
        address _treasuryReceiver,
        address _competitionReceiver
    ) external onlyOwner {
        treasuryReceiver = _treasuryReceiver;
        competitionReceiver = _competitionReceiver;
        lpReceiver = _lpReceiver;
    }

    function getLiquidityBacking(uint256 accuracy)
    public
    view
    returns (uint256)
    {
        uint256 liquidityBalance = _gonBalances[pair].div(_gonsPerFragment);
        return
        accuracy.mul(liquidityBalance.mul(2)).div(getCirculatingSupply());
    }

    function setWhitelist(address _addr) external onlyOwner {
        _isFeeExempt[_addr] = true;
    }

    function setBotBlacklist(address _botAddress, bool _flag) external onlyOwner {
        
        blacklist[_botAddress] = _flag;
    }


    function setPairAddress(address _pairAddress) public onlyOwner {
        pairAddress = _pairAddress;
    }

    function setLP(address _address) external onlyOwner {
        pairContract = IPancakeSwapPair(_address);
    }

    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }

 

    function isContract(address addr) internal view returns (bool) {
        uint size;
        assembly { size := extcodesize(addr) }
        return size > 0;
    }

    receive() external payable {}
}