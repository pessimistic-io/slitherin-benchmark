// SPDX-License-Identifier: Unlicensed 
pragma solidity ^0.8.9; 
 
interface IERC20 { 
    function totalSupply() external view returns (uint256); 
 
    function balanceOf(address account) external view returns (uint256); 
 
    function transfer(address recipient, uint256 amount) external returns (bool); 
 
    function allowance(address owner, address spender) external view returns (uint256); 
 
    function approve(address spender, uint256 amount) external returns (bool); 
 
    function transferFrom( 
        address sender, 
        address recipient, 
        uint256 amount 
    ) external returns (bool); 
 
    event Transfer(address indexed from, address indexed to, uint256 value); 
    event Approval( 
        address indexed owner, 
        address indexed spender, 
        uint256 value 
    ); 
} 
 
interface IUniswapV3Factory { 
    function createPair(address tokenA, address tokenB) 
        external 
        returns (address pair); 
} 
 
interface IUniswapV3Router { 
    function swapExactTokensForETHSupportingFeeOnTransferTokens( 
        uint256 amountIn, 
        uint256 amountOutMin, 
        address[] calldata path, 
        address to, 
        uint256 deadline 
    ) external; 
 
    function factory() external pure returns (address); 
 
    function WETH() external pure returns (address); 
 
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
} 
 
abstract contract Context { 
    function _msgSender() internal view virtual returns (address) { 
        return msg.sender; 
    } 
} 
 
contract Ownable is Context { 
    address private _owner; 
    address private _previousOwner; 
    event OwnershipTransferred( 
        address indexed previousOwner, 
        address indexed newOwner 
    ); 
 
    constructor() { 
        address msgSender = _msgSender(); 
        _owner = msgSender; 
        emit OwnershipTransferred(address(0), msgSender); 
    } 
 
    function owner() public view returns (address) { 
        return _owner; 
    } 
 
    modifier onlyOwner() { 
        require(_owner == _msgSender(), "Ownable: caller is not the owner"); 
        _; 
    } 
 
    function renounceOwnership() public virtual onlyOwner { 
        emit OwnershipTransferred(_owner, address(0)); 
        _owner = address(0); 
    } 
 
    function transferOwnership(address newOwner) public virtual onlyOwner { 
        require(newOwner != address(0), "Ownable: new owner is the zero address"); 
        emit OwnershipTransferred(_owner, newOwner); 
        _owner = newOwner; 
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
}

contract TEST3 is Context, IERC20, Ownable { 
 
    using SafeMath for uint256; 
 
    string private constant _name = "TEST3"; 
    string private constant _symbol = "TEST3"; 
    uint8 private constant _decimals = 9; 
 
    mapping(address => uint256) private _rOwned; 
    mapping(address => uint256) private _tOwned; 
    mapping(address => mapping(address => uint256)) private _allowances; 
    mapping(address => bool) private _isExcludedFromFee; 
    mapping(address => bool) private isTxLimitExept; 
    uint256 private constant MAX = ~uint256(0); 
    uint256 private constant _tTotal = 777777 * 10**9; 
    uint256 private _rTotal = (MAX - (MAX % _tTotal)); 
    uint256 private _tFeeTotal; 
    uint256 private _redisFeeOnBuy = 0; 
    uint256 private _taxFeeOnBuy = 10; 
    uint256 private _redisFeeOnSell = 0;  
    uint256 private _taxFeeOnSell = 14; 
    uint256 public maxTxAmount = (_tTotal * 1) / 100; //1% 
    uint256 public maxWallet = (_tTotal * 2) / 100; //2% 
 
    //Original Fee 
    uint256 private _redisFee = _redisFeeOnSell; 
    uint256 private _taxFee = _taxFeeOnSell; 
 
    uint256 private _previousredisFee = _redisFee; 
    uint256 private _previoustaxFee = _taxFee; 
 
    mapping(address => bool) public bots;  
    mapping (address => uint256) public _buyMap; 
 
    address payable private _jackpotAddress = payable(0x42B9C5cc5ad70471E945545CE4AC025D22841dC4); 
    address payable private _devAddress = payable(0x2dD334c4a3669f1Ae9899e2e8680e87c3B92C107); 
    address payable private _devAddress2 = payable(0x78276F84e6408C7a45ba9c0541C9CEE09bB106EC); 
    address payable private _marketingAddress = payable(0xAd3A65f22a9FD9f7eA789602CEAc4aA88f8b8599); 
    address payable private _royalePoolAddress = payable(0xeF14Ee60DaEd5f7Edd045c7842eE7F72D029527F); 
 
 
    IUniswapV3Router public uniswapV3Router; 
    address public uniswapV3Pair;   
 
    bool private tradingOpen; 
    bool private inSwap = false; 
    bool private swapEnabled = true; 
 
    uint256 public _maxTokenAmount = (_tTotal * 1) / 100; // 1% 
    uint256 public _swapTokensAtAmount = (_tTotal * 1) / 100000; 
 
    modifier lockTheSwap { 
        inSwap = true; 
        _; 
        inSwap = false; 
    } 
 
    constructor() { 
 
        _rOwned[_msgSender()] = _rTotal; 
 
        _isExcludedFromFee[owner()] = true; 
        _isExcludedFromFee[address(this)] = true; 
        _isExcludedFromFee[_jackpotAddress] = true; 
        _isExcludedFromFee[_devAddress] = true; 
        _isExcludedFromFee[_devAddress2] = true; 
        _isExcludedFromFee[_marketingAddress] = true; 
        _isExcludedFromFee[_royalePoolAddress] = true; 
        isTxLimitExept[owner()] = true; 
        isTxLimitExept[address(this)] = true; 
        isTxLimitExept[_royalePoolAddress] = true; 
 
        emit Transfer(address(0), _msgSender(), _tTotal); 
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
 
    function totalSupply() public pure override returns (uint256) { 
        return _tTotal; 
    } 
 
    function balanceOf(address account) public view override returns (uint256) { 
        return tokenFromReflection(_rOwned[account]); 
    } 
 
    function transfer(address recipient, uint256 amount) 
        public 
        override 
        returns (bool) 
    { 
        _transfer(_msgSender(), recipient, amount); 
        return true; 
    } 
 
    function allowance(address owner, address spender) 
        public 
        view 
        override 
        returns (uint256) 
    { 
        return _allowances[owner][spender]; 
    } 
 
    function approve(address spender, uint256 amount) 
        public 
        override 
        returns (bool) 
    { 
        _approve(_msgSender(), spender, amount); 
        return true; 
    } 
 
    function transferFrom( 
        address sender, 
        address recipient, 
        uint256 amount

) public override returns (bool) { 
        _transfer(sender, recipient, amount); 
        _approve( 
            sender, 
            _msgSender(), 
            _allowances[sender][_msgSender()].sub( 
                amount, 
                "ERC20: transfer amount exceeds allowance" 
            ) 
        ); 
        return true; 
    } 
 
    function tokenFromReflection(uint256 rAmount) 
        private 
        view 
        returns (uint256) 
    { 
        require( 
            rAmount <= _rTotal, 
            "Amount must be less than total reflections" 
        ); 
        uint256 currentRate = _getRate(); 
        return rAmount.div(currentRate); 
    } 
 
 
    function removeAllFee() private { 
        if (_redisFee == 0 && _taxFee == 0) return; 
 
        _previousredisFee = _redisFee; 
        _previoustaxFee = _taxFee; 
 
        _redisFee = 0; 
        _taxFee = 0; 
    } 
 
    function restoreAllFee() private { 
        _redisFee = _previousredisFee; 
        _taxFee = _previoustaxFee; 
    } 
 
    function _approve( 
        address owner, 
        address spender, 
        uint256 amount 
    ) private { 
        require(owner != address(0), "ERC20: approve from the zero address"); 
        require(spender != address(0), "ERC20: approve to the zero address"); 
        _allowances[owner][spender] = amount; 
        emit Approval(owner, spender, amount); 
    } 
 
    function setMaxWallet(uint256 amount) external onlyOwner { 
        require(amount >= totalSupply() / 50); //2% 
        maxWallet = amount; 
    } 
 
    function setTxLimit(uint256 amount) external onlyOwner { 
        require(amount >= totalSupply() / 50); //2% 
        maxTxAmount = amount; 
    } 
 
    function checkWalletLimit(address recipient, uint256 amount) internal view { 
        address DEAD = 0x000000000000000000000000000000000000dEaD; 
        if ( 
            recipient != owner() && 
            recipient != address(this) && 
            recipient != address(DEAD) && 
            recipient != uniswapV3Pair && 
            recipient != _royalePoolAddress 
        ) { 
            uint256 heldTokens = balanceOf(recipient); 
            require( 
                (heldTokens + amount) <= maxWallet, 
                "Total Holding is currently limited, you can not buy that much." 
            ); 
        } 
    } 
 
    function checkTxLimit(address sender, uint256 amount) internal view { 
        require( 
            amount <= maxTxAmount || isTxLimitExept[sender], 
            "TX Limit Exceeded" 
        ); 
    } 
 
    function _transfer( 
        address from, 
        address to, 
        uint256 amount 
    ) private { 
        require(from != address(0), "ERC20: transfer from the zero address"); 
        require(to != address(0), "ERC20: transfer to the zero address"); 
        require(amount > 0, "Transfer amount must be greater than zero"); 
 
        if (from != owner() && to != owner()) { 
 
            require(!bots[from] && !bots[to], "TOKEN: Bot!"); 
 
            uint256 contractTokenBalance = balanceOf(address(this)); 
            bool canSwap = contractTokenBalance >= _swapTokensAtAmount; 
 
            if(contractTokenBalance >= _maxTokenAmount) 
            { 
                contractTokenBalance = _maxTokenAmount; 
            } 
 
            if (canSwap && !inSwap && from != uniswapV3Pair && swapEnabled && !_isExcludedFromFee[from] && !_isExcludedFromFee[to]) { 
                swapTokensForEth(contractTokenBalance); 
                uint256 contractETHBalance = address(this).balance; 
                if (contractETHBalance > 0) { 
                    sendETHToFee(address(this).balance); 
                } 
            } 
        } 
 
        bool takeFee = true; 
 
        checkWalletLimit(to, amount); 
        checkTxLimit(from, amount); 
 
        //Transfer Tokens 
        if (_isExcludedFromFee[from] || _isExcludedFromFee[to] || (from == uniswapV3Pair || to == uniswapV3Pair)) {
            takeFee = false; 
        } else {
            //Set Fee for Buys

if(from == uniswapV3Pair && to != address(uniswapV3Router)) { 
                //Trade start check 
                if (!tradingOpen) { 
                    require(from == owner(), "TOKEN: Trading disabled"); 
                } 
                _redisFee = _redisFeeOnBuy; 
                _taxFee = _taxFeeOnBuy; 
            } 
 
            //Set Fee for Sells 
            if (to == uniswapV3Pair && from != address(uniswapV3Router)) { 
                if (!tradingOpen) { 
                    require(from == owner(), "TOKEN: Trading disabled"); 
                } 
                _redisFee = _redisFeeOnSell; 
                _taxFee = _taxFeeOnSell; 
            } 
 
        } 
 
        _tokenTransfer(from, to, amount, takeFee); 
    } 
 
    function swapTokensForEth(uint256 tokenAmount) private lockTheSwap { 
        address[] memory path = new address[](2); 
        path[0] = address(this); 
        path[1] = uniswapV3Router.WETH(); 
        _approve(address(this), address(uniswapV3Router), tokenAmount); 
        uniswapV3Router.swapExactTokensForETHSupportingFeeOnTransferTokens( 
            tokenAmount, 
            0, 
            path, 
            address(this), 
            block.timestamp 
        ); 
    } 
 
    function sendETHToFee(uint256 amount) private { 
        uint256 jackpotAmount = (amount * 50000) / 100000; // 50% 
        uint256 devAddressAmount = (amount * 16666) / 100000; // 8,333% 
        uint256 devAddress2Amount = (amount * 8333) / 100000; // 16,666% 
        uint256 marketingAddressAmount = (amount * 16680) / 100000; // 16,68% 
        uint256 royalePoolAddressAmount = (amount * 8321) / 100000; // 8,321% 
 
        _jackpotAddress.transfer(jackpotAmount); 
        _devAddress.transfer(devAddressAmount); 
        _devAddress2.transfer(devAddress2Amount); 
        _marketingAddress.transfer(marketingAddressAmount); 
        _royalePoolAddress.transfer(royalePoolAddressAmount); 
    } 
 
    function setTrading(bool _tradingOpen) public onlyOwner { 
        tradingOpen = _tradingOpen; 
    } 
 
 
    function addLiquidity() external onlyOwner() { 
        require(!tradingOpen,"trading is already open"); 
        IUniswapV3Router _uniswapV3Router = IUniswapV3Router(0xE592427A0AEce92De3Edee1F18E0157C05861564); 
        uniswapV3Router = _uniswapV3Router; 
        _approve(address(this), address(uniswapV3Router), _tTotal); 
        uniswapV3Pair = IUniswapV3Factory(_uniswapV3Router.factory()).createPair(address(this), _uniswapV3Router.WETH()); 
        uniswapV3Router.addLiquidityETH{value: address(this).balance}(address(this),balanceOf(address(this)),0,0,owner(),block.timestamp); 
        IERC20(uniswapV3Pair).approve(address(uniswapV3Router), type(uint).max); 
    } 
 
    function manualsend() external { 
    require(
        _msgSender() == _jackpotAddress || 
        _msgSender() == _devAddress || 
        _msgSender() == _devAddress2 || 
        _msgSender() == _marketingAddress || 
        _msgSender() == _royalePoolAddress, 
        "Caller must be one of the specified addresses"
    ); 
    uint256 contractETHBalance = address(this).balance; 
    sendETHToFee(contractETHBalance); 
    }

 
    function blockBot(address bot) public onlyOwner { 
        bots[bot] = true; 
    } 
 
    function unblockBot(address notbot) public onlyOwner { 
        bots[notbot] = false; 
    } 
 
    function _tokenTransfer( 
        address sender, 
        address recipient, 
        uint256 amount, 
        bool takeFee 
    ) private { 
        if (!takeFee) removeAllFee(); 
        _transferStandard(sender, recipient, amount); 
        if (!takeFee) restoreAllFee(); 
    } 
 
    function _transferStandard( 
        address sender, 
        address recipient, 
        uint256 tAmount 
    ) private { 
        ( 
            uint256 rAmount,

uint256 rTransferAmount, 
            uint256 rFee, 
            uint256 tTransferAmount, 
            uint256 tFee, 
            uint256 tTeam 
        ) = _getValues(tAmount); 
        _rOwned[sender] = _rOwned[sender].sub(rAmount); 
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount); 
        _takeTeam(tTeam); 
        _reflectFee(rFee, tFee); 
        emit Transfer(sender, recipient, tTransferAmount); 
    } 
 
    function _takeTeam(uint256 tTeam) private { 
        uint256 currentRate = _getRate(); 
        uint256 rTeam = tTeam.mul(currentRate); 
        _rOwned[address(this)] = _rOwned[address(this)].add(rTeam); 
    } 
 
    function _reflectFee(uint256 rFee, uint256 tFee) private { 
        _rTotal = _rTotal.sub(rFee); 
        _tFeeTotal = _tFeeTotal.add(tFee); 
    } 
 
    receive() external payable {} 
 
    function _getValues(uint256 tAmount) 
        private 
        view 
        returns ( 
            uint256, 
            uint256, 
            uint256, 
            uint256, 
            uint256, 
            uint256 
        ) 
    { 
        (uint256 tTransferAmount, uint256 tFee, uint256 tTeam) = 
            _getTValues(tAmount, _redisFee, _taxFee); 
        uint256 currentRate = _getRate(); 
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee) = 
            _getRValues(tAmount, tFee, tTeam, currentRate); 
        return (rAmount, rTransferAmount, rFee, tTransferAmount, tFee, tTeam); 
    } 
 
    function _getTValues( 
        uint256 tAmount, 
        uint256 redisFee, 
        uint256 taxFee 
    ) 
        private 
        pure 
        returns ( 
            uint256, 
            uint256, 
            uint256 
        ) 
    { 
        uint256 tFee = tAmount.mul(redisFee).div(100); 
        uint256 tTeam = tAmount.mul(taxFee).div(100); 
        uint256 tTransferAmount = tAmount.sub(tFee).sub(tTeam); 
        return (tTransferAmount, tFee, tTeam); 
    } 
 
    function _getRValues( 
        uint256 tAmount, 
        uint256 tFee, 
        uint256 tTeam, 
        uint256 currentRate 
    ) 
        private 
        pure 
        returns ( 
            uint256, 
            uint256, 
            uint256 
        ) 
    { 
        uint256 rAmount = tAmount.mul(currentRate); 
        uint256 rFee = tFee.mul(currentRate); 
        uint256 rTeam = tTeam.mul(currentRate); 
        uint256 rTransferAmount = rAmount.sub(rFee).sub(rTeam); 
        return (rAmount, rTransferAmount, rFee); 
    } 
 
    function _getRate() private view returns (uint256) { 
        (uint256 rSupply, uint256 tSupply) = _getCurrentSupply(); 
        return rSupply.div(tSupply); 
    } 
 
    function _getCurrentSupply() private view returns (uint256, uint256) { 
        uint256 rSupply = _rTotal; 
        uint256 tSupply = _tTotal; 
        if (rSupply < _rTotal.div(_tTotal)) return (_rTotal, _tTotal); 
        return (rSupply, tSupply); 
    } 
 
    function setFee(uint256 redisFeeOnBuy, uint256 redisFeeOnSell, uint256 taxFeeOnBuy, uint256 taxFeeOnSell) public onlyOwner { 
        require(redisFeeOnBuy + taxFeeOnBuy <= 15, "Buy tax cannot be greater than 15%"); 
        require(redisFeeOnSell + taxFeeOnSell <= 15, "Sell tax cannot be greater than 15%"); 
        _redisFeeOnBuy = redisFeeOnBuy; 
        _redisFeeOnSell = redisFeeOnSell; 
        _taxFeeOnBuy = taxFeeOnBuy; 
        _taxFeeOnSell = taxFeeOnSell; 
    } 
 
    //Set minimum tokens required to swap. 
    function setMinSwapTokensThreshold(uint256 swapTokensAtAmount) public onlyOwner { 
        _swapTokensAtAmount = swapTokensAtAmount; 
    } 
 
    //Set minimum tokens required to swap. 
    function toggleSwap(bool _swapEnabled) public onlyOwner { 
        swapEnabled = _swapEnabled; 
    } 
 
    //Set maximum transaction 
    function setMaxTokenAmount(uint256 maxTokenAmount) public onlyOwner { 
        _maxTokenAmount = maxTokenAmount; 
    } 
 
    function updateJackpotAddress(address payable newJackpotAddress) public onlyOwner{ 
        _jackpotAddress = newJackpotAddress; 
    }

function updateDevAddress(address payable newDevAddress) public onlyOwner{ 
        _devAddress = newDevAddress; 
    } 
 
    function updateDevAddress2(address payable newDevAddress2) public onlyOwner{ 
        _devAddress2 = newDevAddress2; 
    } 
 
    function updateMarketingAddress(address payable newMarketingAddress) public onlyOwner{ 
        _marketingAddress = newMarketingAddress; 
    } 
 
    function updateRoyalePoolAddress(address payable newRoyalePoolAddress) public onlyOwner{ 
        _royalePoolAddress = newRoyalePoolAddress; 
    } 
 
    function excludeMultipleAccountsFromFees(address[] calldata accounts, bool excluded) public onlyOwner { 
        for(uint256 i = 0; i < accounts.length; i++) { 
            _isExcludedFromFee[accounts[i]] = excluded; 
        } 
    } 
 
}