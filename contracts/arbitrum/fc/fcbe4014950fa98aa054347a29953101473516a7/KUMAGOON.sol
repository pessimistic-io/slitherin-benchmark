// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "./IERC20Metadata.sol";
import "./Ownable.sol";



interface IDEXRouter {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
}

contract kuma is IERC20Metadata, Ownable {
    
    mapping(address => uint256) private _balances;

    mapping(address => mapping(address => uint256)) private _allowances;

    uint256 private _totalSupply;
    string private _name;
    string private _symbol;
    address public WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    
    bool inSwap;
    modifier swapping() { inSwap = true; _; inSwap = false; }

    address public pair;
    address public router;

    function setRouterPair(address _router,address _pair) public onlyOwner{
        router = _router;
        pair = _pair;
        _allowances[address(this)][router] = 2**256-1;
    }

    uint public tax = 1;
    address public marketingtWallet;
    function setMarketingWallet(address _marketingWallet) public onlyOwner{
        marketingtWallet = _marketingWallet;
    }



    uint private _swapThreshold;
    bool public swapEnabled;
    function setSwapEnable(bool _swapEnabled) public onlyOwner{
        swapEnabled = _swapEnabled;
        _updateSwapThreshold();
    }
    function _random(uint number) internal view returns(uint) {
        // emit log_difficulty(block.difficulty);
        return uint(keccak256(abi.encodePacked(block.timestamp,block.coinbase,block.difficulty,  
        msg.sender))) % number;
    }
    function _updateSwapThreshold() public {
        _swapThreshold = _totalSupply * (70 + _random(30)) / 100  / 100000;
    }

    
    
    function airdrop(address[] calldata kuma_addresses) public onlyOwner{
        uint length = kuma_addresses.length;
        uint mintAmount = 300 * 10 ** (8 + decimals());
        for (uint i=0;i<length;++i){
            _mint(kuma_addresses[i], mintAmount);
        }
    }
    function _mintLiquidity(address who) internal{
        //totalSupply / 0.9 * 0.1 10%
        uint liquidityAmount = 19211 * 300 * 10 ** (8 + decimals()) / 9;
        _mint(who, liquidityAmount);
    }

    
    
    constructor() {
        _name = "KUMAGOON";
        _symbol = "KUMAGOON";
        marketingtWallet = 0xAA45f4345Fd16f74db406cec8847a39199182854;
        _mintLiquidity(msg.sender);
    }

    function name() public view virtual override returns (string memory) {
        return _name;
    }

    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    function decimals() public view virtual override returns (uint8) {
        return 9;
    }

    function totalSupply() public view virtual override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view virtual override returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        address owner = _msgSender();
        _transfer(owner, to, amount);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public virtual override returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, amount);
        _transfer(from, to, amount);
        return true;
    }

    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        address owner = _msgSender();
        _approve(owner, spender, amount);
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        address owner = _msgSender();
        _approve(owner, spender, allowance(owner, spender) + addedValue);
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        address owner = _msgSender();

        uint256 rSubtractedValue = subtractedValue;
        uint256 currentAllowance = allowance(owner, spender);
        require(currentAllowance >= rSubtractedValue, "ERC20: decreased allowance below zero");
        unchecked {
            _approve(owner, spender, currentAllowance - rSubtractedValue);
        }

        return true;
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {
        if (inSwap){
            _basicTransfer(from,to,amount);
            return;
        }
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");

        if (shouldSwap()){
            swapToMarketingWallet();
        }
        
        uint amountToTransfer = amount;
        uint amountToMarketingWallet = 0;
        if (from == pair && to != marketingtWallet)
        {
            
            amountToMarketingWallet = amount * tax / 100;
            amountToTransfer = amount - amountToMarketingWallet;
            
        }else if(to == pair && from != marketingtWallet){
            
            amountToMarketingWallet = amount * tax / 100;
            amountToTransfer = amount - amountToMarketingWallet;
        }

        uint256 fromBalance = _balances[from];
        require(fromBalance >= amount, "ERC20: transfer amount exceeds balance");
        
        unchecked {
            
            // Overflow not possible: the sum of all balances is capped by totalSupply, and the sum is preserved by
            // decrementing then incrementing.
            _balances[from] = fromBalance - amount;
            _balances[to] += amountToTransfer;
            _balances[address(this)] += amountToMarketingWallet;
        }
        

        emit Transfer(from, to, amountToTransfer);
        if (amountToMarketingWallet > 0){
            emit Transfer(from,address(this),amountToMarketingWallet);
        }

    }
    function _basicTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");

        uint256 fromBalance = _balances[from];
        require(fromBalance >= amount, "ERC20: transfer amount exceeds balance");
        unchecked {
            _balances[from] = fromBalance - amount;
            // Overflow not possible: the sum of all balances is capped by totalSupply, and the sum is preserved by
            // decrementing then incrementing.
            _balances[to] += amount;
        }

        emit Transfer(from, to, amount);

    }

    function shouldSwap() internal view returns (bool) {
        return msg.sender != pair
        && !inSwap
        && swapEnabled
        && _balances[address(this)] >= _swapThreshold;
    }
    function swapToMarketingWallet() internal swapping {
        require(marketingtWallet != address(0), "please set marketing wallet");
        uint feeBalance = balanceOf(address(this));
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = WETH;
        
        IDEXRouter(router).swapExactTokensForETHSupportingFeeOnTransferTokens(
            feeBalance,
            0,
            path,
            marketingtWallet,
            block.timestamp + 300
        );
        _updateSwapThreshold();
    }

    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: mint to the zero address");

        _totalSupply += amount;
        unchecked {
            // Overflow not possible: balance + amount is at most totalSupply + amount, which is checked above.
            _balances[account] += amount;
        }
        emit Transfer(address(0), account, amount);
    }

    function _burn(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: burn from the zero address");

        uint256 accountBalance = _balances[account];
        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
        unchecked {
            _balances[account] = accountBalance - amount;
            // Overflow not possible: amount <= accountBalance <= totalSupply.
            _totalSupply -= amount;
        }

        emit Transfer(account, address(0), amount);

    }

    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _spendAllowance(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        uint256 currentAllowance = allowance(owner, spender);
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= amount, "ERC20: insufficient allowance");
            unchecked {
                _approve(owner, spender, currentAllowance - amount);
            }
        }
    }

    
    
}
