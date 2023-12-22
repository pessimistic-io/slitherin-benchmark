// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.11;

import "./ERC20.sol";
import "./Ownable.sol";
import "./ISwapRouter.sol";
import "./IUniswapV3Factory.sol";
import "./IReservesManager.sol";

contract Mount is ERC20, Ownable {
    IReservesManager public immutable reservesManager;
    address public immutable uniswapPool;
    address public constant deadAddress = address(0xdead);

    uint256 public supply;
    address public reservesWallet;

    /******************/

    // exlcude from fees and max transaction amount
    mapping(address => bool) private _isExcludedFromFees;

    // store addresses that a automatic market maker pairs. Any transfer *to* these addresses
    // could be subject to a maximum transfer amount
    mapping(address => bool) public automatedMarketMakerPools;

    constructor(address _reservesManagerAddress) ERC20("Mount Token", "MOUNT") {
        ISwapRouter _uniswapV3Router = ISwapRouter(
            0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45
        );

        uniswapPool = IUniswapV3Factory(_uniswapV3Router.factory()).createPool(
            address(this),
            address(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8), //USDC
            uint24(10000)
        );

        reservesManager = IReservesManager(_reservesManagerAddress);

        _setAutomatedMarketMakerPool(uniswapPool, true);

        uint256 totalSupply = 3 * 1e5 * 1e18;
        supply = totalSupply;

        reservesWallet = _reservesManagerAddress;

        excludeFromFees(owner(), true);
        excludeFromFees(address(this), true);
        excludeFromFees(deadAddress, true);

        _approve(owner(), address(_uniswapV3Router), totalSupply);
        _mint(msg.sender, totalSupply);
    }

    receive() external payable {}

    function updateReservesWallet(address newWallet) external onlyOwner {
        reservesWallet = newWallet;
    }

    function excludeFromFees(address account, bool excluded) public onlyOwner {
        _isExcludedFromFees[account] = excluded;
    }

    function setAutomatedMarketMakerPool(address pool, bool value)
        public
        onlyOwner
    {
        require(
            pool != uniswapPool,
            "The pair cannot be removed from automatedMarketMakerPools"
        );

        _setAutomatedMarketMakerPool(pool, value);
    }

    function _setAutomatedMarketMakerPool(address pool, bool value) private {
        automatedMarketMakerPools[pool] = value;
    }

    function isExcludedFromFees(address account) public view returns (bool) {
        return _isExcludedFromFees[account];
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");

        if (amount == 0) {
            super._transfer(from, to, 0);
            return;
        }

        bool isSelling = automatedMarketMakerPools[to];
        bool isBuying = automatedMarketMakerPools[from];

        uint256 fees = 0;
        uint256 tokensForBurn = 0;

        bool takeFee = true;

        if (_isExcludedFromFees[from] || _isExcludedFromFees[to]) {
            takeFee = false;
        }

        // If take fees
        if (takeFee) {
            // (no variable needed) : tokensForTreasury  = fees - tokensForBurn
            (fees, tokensForBurn) = reservesManager.estimateFees(
                isSelling,
                isBuying,
                amount
            );

            if (fees > 0) {
                super._transfer(from, address(this), fees);
                if (tokensForBurn > 0) {
                    _burn(address(this), tokensForBurn);
                    supply = totalSupply();
                    tokensForBurn = 0;
                }
            }

            amount -= fees;
        }
        super._transfer(from, to, amount);
    }
}
