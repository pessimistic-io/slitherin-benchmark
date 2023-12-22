pragma solidity ^0.6.12;

import "./ERC20.sol";

import "./IUniswapV2Factory.sol";
import "./IUniswapV2Router02.sol";
import "./IUniswapV2Pair.sol";

contract WowToken is IERC20 {
    using SafeMath for uint256;

    IUniswapV2Router02 public immutable uniswapV2Router;

    mapping(address => uint256) private _balances;

    mapping(address => mapping(address => uint256)) private _allowances;

    string internal _name;

    string internal _symbol;

    uint8 internal _decimals;

    uint256 private _totalSupply;

    address public immutable uniswapV2Pair;


    address public burnAddress = 0x000000000000000000000000000000000000dEaD;
    address public LFG = 0xF7a0b80681eC935d6dd9f3Af9826E68B99897d6D;


    constructor() public {
        _name = "Wow Token";
        _symbol = "WOW";
        _decimals = 18;
        uint total = 1000000000 * 10**18;
        // 10% pool
        _mint(msg.sender, total);

        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(0xF83675ac64a142D92234681B7AfB6Ba00fa38dFF);
   
        uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory()).pairFor(address(this), LFG);
        uniswapV2Router = _uniswapV2Router;
    }

    function name() public view virtual  returns (string memory) {
        return _name;
    }

    function symbol() public view virtual  returns (string memory) {
        return _symbol;
    }

    function decimals() public view virtual returns (uint8) {
        return _decimals;
    }

    function totalSupply() public view virtual override returns (uint256) {
        return _totalSupply;
    }

    function burn(uint256 amount)
        public
        virtual
        returns (bool)
    {
        _burn(msg.sender, amount);

        return true;
    }

    function balanceOf(address account)
        public
        view
        virtual
        override
        returns (uint256)
    {
        return _balances[account];
    }

    function transfer(address to, uint256 amount)
        public
        virtual
        override
        returns (bool)
    {
        _transfer(msg.sender, to, amount);

        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public virtual override returns (bool) {
        _spendAllowance(from, msg.sender, amount);
        _transfer(from, to, amount);

        return true;
    }

    function approve(address spender, uint256 amount)
        public
        virtual
        override
        returns (bool)
    {
        _approve(msg.sender, spender, amount);

        return true;
    }

    function allowance(address owner, address spender)
        public
        view
        virtual
        override
        returns (uint256)
    {
        return _allowances[owner][spender];
    }

    function increaseAllowance(address spender, uint256 addedValue)
        public
        virtual
        returns (bool)
    {
        _approve(
            msg.sender,
            spender,
            allowance(msg.sender, spender) + addedValue
        );
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue)
        public
        virtual
        returns (bool)
    {
        uint256 currentAllowance = allowance(msg.sender, spender);
        require(
            currentAllowance >= subtractedValue,
            "ERC20: decreased allowance below zero"
        );
        // unchecked {
            _approve(msg.sender, spender, currentAllowance - subtractedValue);
        // }

        return true;
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");

        uint256 fromBalance = _balances[from];
        require(
            fromBalance >= amount,
            "ERC20: transfer amount exceeds balance"
        );
        // unchecked {
            _balances[from] = fromBalance - amount;
        // }
     
     
        bool takeFee = false;
        // add or sell
        if(to == address(uniswapV2Pair) && address(this) != from){
            takeFee = true;
            (uint reserve0, uint reserve1, ) = IUniswapV2Pair(uniswapV2Pair).getReserves();
            if(address(this) == IUniswapV2Pair(uniswapV2Pair).token0() && IERC20(LFG).balanceOf(uniswapV2Pair) != reserve1){
                takeFee = false;
            }
            if(address(this) == IUniswapV2Pair(uniswapV2Pair).token1() && IERC20(LFG).balanceOf(uniswapV2Pair) != reserve0){
                takeFee = false;
            }
        }
        // sell 5%
        if(takeFee == true) {
            uint burnAmount = amount.mul(5).div(100);
            amount = amount.sub(burnAmount);
            
            _balances[burnAddress] = _balances[burnAddress].add(burnAmount);
            emit Transfer(from, burnAddress, burnAmount);
        }
       
         _balances[to] = _balances[to].add(amount);
        emit Transfer(from, to, amount);
    }

    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: mint to the zero address");

        _totalSupply += amount;
        _balances[account] += amount;

        emit Transfer(address(0), account, amount);
    }

    function _burn(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: burn from the zero address");

        uint256 accountBalance = _balances[account];
        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
        // unchecked {s
            _balances[account] = accountBalance - amount;
        // }
        _totalSupply -= amount;

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
            require(
                currentAllowance >= amount,
                "ERC20: insufficient allowance"
            );
            // unchecked {
                _approve(owner, spender, currentAllowance - amount);
            // }
        }
    }

}

