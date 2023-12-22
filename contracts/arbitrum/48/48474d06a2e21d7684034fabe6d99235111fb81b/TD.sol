// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./ERC20.sol";

import "./IUniswapV2Factory.sol";
import "./IUniswapV2Router02.sol";

contract TD is ERC20, Ownable {
    uint256 public constant FEE = 198;
    uint256 public constant BASE = 10000;

    address public immutable usdt;
    address public immutable router;

    address public pool;
    uint256 public threshold;

    mapping(address => bool) public pairs;

    bool public _swapping;
    modifier swapping() {
        _swapping = true;
        _;
        _swapping = false;
    }

    constructor(address _usdt, address _router) ERC20("TD", "TD") {
        _mint(_msgSender(), 1000000000000000 * (10 ** decimals()));

        usdt = _usdt;
        router = _router;

        // address pair = IUniswapV2Factory(IUniswapV2Router02(router).factory()).createPair(address(this), usdt);
        // pairs[pair] = true;

        _approve(address(this), router, type(uint256).max);
    }

    function decimals() public view virtual override returns (uint8) {
        return 6;
    }

    function setPool(address newPool) public onlyOwner {
        pool = newPool;
    }

    function setThreshold(uint256 newThreshold) public onlyOwner {
        threshold = newThreshold;
    }

    function setPair(address pair, bool state) public onlyOwner {
        pairs[pair] = state;
    }

    function _transfer(address from, address to, uint256 amount) internal override {
        if ((pairs[from] != true && pairs[to] != true) || _swapping) {
            super._transfer(from, to, amount);
            return;
        }

        if (pairs[to] == true) {
            _swap();
        }

        uint256 fee = (amount * FEE) / BASE;
        super._transfer(from, address(this), fee);
        super._transfer(from, to, amount - fee);
    }

    function _swap() internal swapping {
        uint256 amount = balanceOf(address(this));
        if (amount <= threshold) return;

        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = usdt;
        IUniswapV2Router02(router).swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amount,
            0,
            path,
            pool,
            block.timestamp
        );
    }
}

