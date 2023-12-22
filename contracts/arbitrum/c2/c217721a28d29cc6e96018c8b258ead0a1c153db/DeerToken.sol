// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./ERC20.sol";
import "./Ownable.sol";
import "./SafeMath.sol";
import "./IUniswapV2Router02.sol";
import "./IUniswapV2Factory.sol";
import "./ERC20Burnable.sol";

// Version 1.0.0
contract DeerToken is ERC20, Ownable, ERC20Burnable {
    using SafeMath for uint256;
    uint public constant PERCENT_DIVIDER = 1000;
    uint public constant FEE = 50; // fee 5%

    IUniswapV2Router02 public ROUTER;
    IUniswapV2Factory public FACTORY;

    address public ROUTER_MAIN =
        address(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506);
    address[5] private tokenPairs = [
        0x912CE59144191C1204E64559FE8253a0e49E6548, // Arbitrum
        0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9, // Tether USDT
        0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8, // USD Coin (Arb1)
        0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f, // Wrapped BTC
        0xd4d42F0b6DEF4CE0383636770eF773390d85c61A // Sushi Token
    ];
    address public liquidityWallet = 0xa6f46aF64252EE96418AeE3423e55261979abe7a;

    mapping(address => bool) public sushiSwapPair;
    uint256 private constant DECIMALS = 10 ** 18;

    constructor() ERC20("DEER PROTOCOL", "DEER") {
        _mint(msg.sender, 250000 * DECIMALS);
        ROUTER = IUniswapV2Router02(ROUTER_MAIN);
        FACTORY = IUniswapV2Factory(ROUTER.factory());
        initializePairs();
        approve(ROUTER_MAIN, 250000 * DECIMALS);
    }

    function initializePairs() private {
        address pair = FACTORY.createPair(address(this), ROUTER.WETH());
        sushiSwapPair[pair] = true;

        for (uint i = 0; i < tokenPairs.length; i++) {
            pair = FACTORY.createPair(address(this), tokenPairs[i]);
            sushiSwapPair[pair] = true;
        }
    }

    function _transfer(
        address sender,
        address receiver,
        uint256 amount
    ) internal virtual override {
        uint256 taxAmount = amount.mul(FEE).div(PERCENT_DIVIDER);
        _burn(sender, taxAmount.div(2)); // BURN // 2.5  %
        super._transfer(sender, liquidityWallet, taxAmount.div(2)); // Send %  2.5  to
        amount = amount.sub(taxAmount);
        super._transfer(sender, receiver, amount);
    }

    fallback() external {
        revert();
    }
}

