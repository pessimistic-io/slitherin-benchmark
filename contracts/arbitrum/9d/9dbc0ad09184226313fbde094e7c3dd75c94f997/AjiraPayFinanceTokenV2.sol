// SPDX-License-Identifier: MIT
pragma solidity =0.8.4;
import "./Ownable.sol";
import "./ERC1363.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";
import "./ERC20Burnable.sol";

interface IPancakeswapV2Factory {
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

interface IPancakeSwapV2Pair {
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

interface IPancakeRouter01 {
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

interface IPancakeRouter02 is IPancakeRouter01 {
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

contract AjiraPayFinanceTokenV2 is Ownable, ERC1363,ReentrancyGuard, ERC20Burnable{ 
    using SafeERC20 for IERC20;
    uint256 private _totalSupply = 200_000_000 * 1e18;
    string private _name = 'Ajira Pay Finance';
    string private _symbol = 'AJP';

    IPancakeRouter02 public pancakeswapV2Router;
    address public pancakeswapV2Pair;
    address payable public treasury;
    address payable public autoLiquidityReceiver;
    address private constant DEAD = 0x000000000000000000000000000000000000dEaD;

    bool inSwapAndLiquify;
    bool public swapAndLiquifyEnabled = false;
    bool public isInTaxHoliday = false;
    bool public isBuyBackEnabled = true;
    bool public isAutoLiquidityEnabled = true;

    mapping(address => bool) public isExcludedFromFee;

    uint256 public buyFee;
    uint256 public sellFee;
    uint256 public minLiquidityAmount; 
    uint256 public liquidityTreasuryPercent;
    uint256 public buyBackTreasuryPercent;
    uint256 public devTreasuryPercent;
    
    event SwapAndLiquify(
        uint256 tokensSwapped,
        uint256 ethReceived,
        uint256 tokensIntoLiqudity
    );

    event SetTreasuryPercentages(
        address indexed caller, 
        uint256 indexed buyBackTreasuryPercent, 
        uint256 indexed liquityTreasuryPercent, 
        uint256 timestamp
    );
    
    event UpdatePancakeswapPair(
        address indexed caller,
        address indexed newPair,
        uint256 indexed timestamp
    );

    event ExcludeFromFees(
        address indexed account,
        address indexed caller,
        uint256 indexed timestamp
    );

    event IncludeInFees(
        address indexed account,
        address indexed caller,
        uint256 indexed timestamp
    );
    
    event SetAutoLiquidityEnabled(
        address indexed caller,
        bool indexed autoLiquidityStatus,
        uint256 indexed timestamp
    );

    event UpdateFees(
        address indexed caller,
        uint256 indexed buyFeePercent,
        uint256 indexed sellFeePercent,
        uint256 timestamp
    );

    event UpdateRouter(
        address indexed caller,
        address indexed newRouter,
        uint256 indexed timestamp
    );

    event UpdateTreasury(
        address indexed caller,
        address payable indexed newTreasury,
        uint256 indexed timestamp
    );

    event UpdateMinLiquidityAmount(
        address indexed caller,
        uint256 indexed minTokensToLiquify,
        uint256 indexed timestamp
    );

    event SetBuyBackEnabled(
        address indexed caller,
        bool indexed isBuyBackEnabled,
        uint256 indexed timestamp
    );
    
    event RecoverLostTokens(
        address indexed caller,
        address indexed destination,
        address indexed token,
        uint256 tokenAmount,
        uint256 timestamp
    );

    event SetSwapEnabled(
        address indexed caller, 
        bool indexed isSwapEnabled,
        uint256 indexed timestamp
    );
    
    event UpdateTaxHolidatStatus(
        address indexed caller,
        bool indexed isFeeHolidayEnabled,
        uint256 indexed timestamp

    );

    event UpdateLiquidityReceiver(
        address indexed caller,
        address payable indexed liquidityReceiver,
        uint256 indexed timestamp
    );

    event AddLiquidity(
        uint256 indexed tokenAmount, 
        uint256 indexed bnbAmount
    );

    event BuyBackAndBurn(
        uint256 indexed bnbAmountBurned
    );

    event TakeTax(
        uint256 tokenAmount
    );

    modifier swapping{
        inSwapAndLiquify = true;
        _;
        inSwapAndLiquify = false;
    }

    constructor(address _router, address payable _treasury) ERC20(_name, _symbol){
        require(_router != address(0),"Invalid Address");
        require(_treasury != address(0),"Invalid Address");

        treasury = _treasury;
        autoLiquidityReceiver = payable(msg.sender);

        IPancakeRouter02 _pancakeSwapV2Router = IPancakeRouter02(_router);
        pancakeswapV2Pair = IPancakeswapV2Factory(_pancakeSwapV2Router.factory()).createPair(
            address(this), 
            _pancakeSwapV2Router.WETH());

        pancakeswapV2Router = _pancakeSwapV2Router;

        isExcludedFromFee[msg.sender] = true;
        isExcludedFromFee[address(this)] = true;
        isExcludedFromFee[DEAD] = true;
        isExcludedFromFee[treasury] = true;

        //Percentages 100 = 1% ;1000 = 10%; 10000 = 100%
        buyFee = 100;//1%
        sellFee = 200;//2%

        liquidityTreasuryPercent = 1000;//10%
        buyBackTreasuryPercent = 4000; //40%
        devTreasuryPercent = 5000;//50%
    
        minLiquidityAmount = 1_000_000 * 1e18;
        _mint(msg.sender, _totalSupply);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC1363) returns (bool) {
        return 
            interfaceId == type(IERC1363).interfaceId ||
            interfaceId == type(IERC165).interfaceId ||
            interfaceId == type(IERC20Metadata).interfaceId ||
            interfaceId == type(IERC20).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    function recoverLostTokensForInvestor(address _token, uint _amount) public onlyOwner nonReentrant{
        require(_token != address(this), "Invalid Token Address");
        IERC20(_token).safeTransfer(msg.sender, _amount);
        emit RecoverLostTokens(msg.sender, msg.sender, _token, _amount, block.timestamp);
    }
    
    function updateTreasury(address payable _newTreasury) public onlyOwner{
        require(_newTreasury != address(0),"Invalid Address");
        treasury = _newTreasury;
        isExcludedFromFee[treasury] = true;
        emit UpdateTreasury(msg.sender, _newTreasury, block.timestamp);
    }

    function updateRouterAddress(address _newRouter) external onlyOwner {
        require(_newRouter != address(0),"Invalid Router Address");
        IPancakeRouter02 _pancakeSwapV2Router = IPancakeRouter02(_newRouter);
        pancakeswapV2Pair = IPancakeswapV2Factory(_pancakeSwapV2Router.factory()).createPair(
            address(this), 
            _pancakeSwapV2Router.WETH()); 
        pancakeswapV2Router = _pancakeSwapV2Router;
        emit UpdateRouter(msg.sender, _newRouter, block.timestamp);
    }

    function setDeductionFeePercentages(uint256 _buyFee, uint256 _sellFee) public onlyOwner nonReentrant{
        uint256 feeTotals = _buyFee + _sellFee;
        require(feeTotals <= 1000,"Fees Cannot Exceed 10%");
        buyFee = _buyFee;
        sellFee = _sellFee;
        emit UpdateFees(msg.sender, _buyFee, _sellFee, block.timestamp);
    }

    function setTreasuryPercentages(uint256 _liquidity, uint256 _buyBack, uint256 _dev) public onlyOwner nonReentrant{
        uint256 totalTreasuryAmount = _liquidity + _buyBack + _dev;
        require(totalTreasuryAmount <= 10000,"Total Treasury cannot exceed 100%");
        liquidityTreasuryPercent = _liquidity;
        buyBackTreasuryPercent = _buyBack;
        devTreasuryPercent = _dev;
        emit SetTreasuryPercentages(msg.sender, _buyBack, _liquidity, block.timestamp);
    }

    function setSwapAndLiquifyEnabled(bool _enabled) public onlyOwner{
        swapAndLiquifyEnabled = _enabled;
        emit SetSwapEnabled(msg.sender, _enabled, block.timestamp);
    }

    function excludeFromFee(address _account) public onlyOwner{
        isExcludedFromFee[_account] = true;
        emit ExcludeFromFees(_account, msg.sender, block.timestamp);
    }

    function includeInFee(address _account) public onlyOwner{
        isExcludedFromFee[_account] = false;
        emit IncludeInFees(_account, msg.sender, block.timestamp);
    }

    function setTaxHolidayEnabled(bool _enabled) public onlyOwner{
        isInTaxHoliday = _enabled;
        emit UpdateTaxHolidatStatus(msg.sender, _enabled, block.timestamp);
    }

    function setBuyBackEnabled(bool _enabled) public onlyOwner{
        isBuyBackEnabled = _enabled;
        emit SetBuyBackEnabled(msg.sender, _enabled, block.timestamp);
    }

    function updateMinTokensToLiquify(uint256 _amount) public onlyOwner nonReentrant{
        require(_amount > 0, "Invalid Liquidity Amount");
        minLiquidityAmount = _amount * 1e18;
        emit UpdateMinLiquidityAmount(msg.sender, _amount, block.timestamp);
    }

    function updateAutoLiquidityStatus(bool _liquidityStatus) external onlyOwner{
        isAutoLiquidityEnabled = _liquidityStatus;
        emit SetAutoLiquidityEnabled(msg.sender, _liquidityStatus, block.timestamp);
    }

    function updatePancakeswapPair(address _newPair) external onlyOwner{
        require(_newPair != address(0),"Invalid Pair Address");
        require(_newPair != pancakeswapV2Pair,"Pair Already Exists");
        pancakeswapV2Pair = _newPair;
        emit UpdatePancakeswapPair(msg.sender, _newPair, block.timestamp);
    }

    function setAutoLiquidityReceiver(address payable _receiver) external onlyOwner{
        autoLiquidityReceiver = _receiver;
        emit UpdateLiquidityReceiver(msg.sender, _receiver, block.timestamp);
    }

    receive() external payable {}

    function _transfer(address _sender, address _recipient, uint _amount) internal virtual override {
        require(_amount > 0, "Amount Cannot Be Zero");
        require(_sender != address(0), "Invalid Address");
        require(_recipient != address(0), "Invalid Address");

        uint256 contractTokenBalance = balanceOf(address(this));

        bool overMinTokenBalance = contractTokenBalance >= minLiquidityAmount;

        if (
            overMinTokenBalance &&
            !inSwapAndLiquify &&
            _sender != pancakeswapV2Pair &&
            swapAndLiquifyEnabled
        ) {
                contractTokenBalance = minLiquidityAmount;
                _swapAndLiquify(contractTokenBalance);
            }

            bool takeFee = true;
            if(isExcludedFromFee[_sender] || isExcludedFromFee[_recipient]){
                takeFee = false;
            } 
            if(isInTaxHoliday){
                takeFee = false;
            }
            uint256 amountReceived = (takeFee) ? _takeTaxes(_sender, _recipient, _amount) : _amount;
            super._transfer(_sender, _recipient, amountReceived);
    }

    function _swapAndLiquify(uint256 contractTokenBalance) internal swapping{
      uint256 half = contractTokenBalance / 2;
      uint256 otherHalf = contractTokenBalance - half;
      uint256 initialBalance = address(this).balance;

      _swapTokensForBnb(half); 

      uint256 newBalance = address(this).balance - initialBalance;

      (uint256 liquidityTreasuryAmount, uint256 buyBackTreasuryAmount, uint256 devTreasuryAmount) = _calculateTreasuryAmountFromBNB(newBalance);
      
      if(devTreasuryAmount > 0){
        payable(treasury).transfer(devTreasuryAmount);
      }

      if(isAutoLiquidityEnabled && liquidityTreasuryAmount > 0){
          _addLiquidity(address(this), otherHalf, liquidityTreasuryAmount);
      }

      if(isBuyBackEnabled && buyBackTreasuryAmount > 0){
        _buyBackAndBurnTokens(buyBackTreasuryAmount);
      }
      
      emit SwapAndLiquify(half, liquidityTreasuryAmount, otherHalf);
    }

    function _swapTokensForBnb(uint256 _tokenAmount) internal{
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = pancakeswapV2Router.WETH();
        _approve(address(this), address(pancakeswapV2Router), _tokenAmount);
        pancakeswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            _tokenAmount,
            0, // accept any amount of BNB
            path,
            address(this),
            block.timestamp
        );
    }

    function _addLiquidity(address _token, uint256 _tokenAmount, uint256 _bnbAmount) internal{
        IERC20(_token).approve(address(pancakeswapV2Router), _tokenAmount);
        pancakeswapV2Router.addLiquidityETH{value: _bnbAmount}(
            address(this),
            _tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            autoLiquidityReceiver,
            block.timestamp
        );
        emit AddLiquidity(_tokenAmount, _bnbAmount);
    }

    function _buyBackAndBurnTokens(uint256 _bnbAmount) internal{
        address[] memory path = new address[](2);
        path[0] = pancakeswapV2Router.WETH();
        path[1] = address(this);
        _approve(address(this), address(pancakeswapV2Router), _bnbAmount);
         pancakeswapV2Router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: _bnbAmount}(
            0, // accept any amount of Tokens
            path,
            DEAD,
            block.timestamp
        );    
        emit BuyBackAndBurn(_bnbAmount);
    }

    function _takeTaxes(address from, address to, uint256 amount) private returns (uint256) {
        uint256 currentFee;
        if (from == pancakeswapV2Pair) {
            currentFee = buyFee;
        } else if (to == pancakeswapV2Pair) {
            currentFee = sellFee;
        }else{
            currentFee = 0;
        } 
        
        uint256 feeAmount = amount * currentFee / 10000;
        if(feeAmount > 0){
            super._transfer(from, address(this), feeAmount);
            emit TakeTax(feeAmount);
        }
        return amount - feeAmount;
    }

    function _calculateTreasuryAmountFromBNB(uint256 _amount) private view returns(uint256, uint256, uint256){
        uint256 liquidity = _amount * liquidityTreasuryPercent / 10000;
        uint256 buyBack = _amount * buyBackTreasuryPercent / 10000;
        uint256 dev = _amount * devTreasuryPercent / 10000;
        return (liquidity, buyBack, dev);
    }
}
