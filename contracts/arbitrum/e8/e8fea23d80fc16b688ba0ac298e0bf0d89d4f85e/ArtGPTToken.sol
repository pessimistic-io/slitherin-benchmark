// SPDX-License-Identifier: GPL3.0
pragma solidity ^0.8.4;
import "./Ownable.sol";
import "./ERC20.sol";
import "./IPancakeFactory.sol";
import "./IPancakeRouter02.sol";
import "./console.sol";

contract ArtGPTToken is ERC20, Ownable {
    uint256 public constant supply = 1e9 * 1e18;

    IPancakeRouter02 public uniswapV2Router;
    address public uniswapV2Pair;
    address public marketingWallet;
    uint256 public buyTaxRate = 2; // 2% tax buy
    uint256 public sellTaxRate = 5; // 5% tax sell
    bool inSwap = false;

    mapping(address => bool) private isExcludedFromFee;

    uint256 public fightingBotActive = 400 * 1e18;
    uint256 public minSwapAmount = 5000 * 1e18;

    uint256 public fightingBotDuration = 10; //seconds
    uint256 public fightingBot;

    constructor(
        string memory name,
        string memory symbol,
        address _router
    ) ERC20(name, symbol) {
        IPancakeRouter02 _uniswapV2Router = IPancakeRouter02(_router);
        uniswapV2Pair = IPancakeFactory(_uniswapV2Router.factory())
            .createPair(address(this), _uniswapV2Router.WETH());

        uniswapV2Router = _uniswapV2Router;

        _mint(_msgSender(), supply);
        isExcludedFromFee[_msgSender()] = true;
        marketingWallet = _msgSender();
    }

    modifier onlyMarketingWallet() {
        require(_msgSender() == marketingWallet, "Only Marketing Wallet!");
        _;
    }

    modifier swapping() {
        inSwap = true;
        _;
        inSwap = false;
    }

    function burn(uint256 amount) public {
        _burn(_msgSender(), amount);
    }

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal virtual override {
        console.log(amount);
        uint256 transferTaxRate = (recipient == uniswapV2Pair &&
            isExcludedFromFee[sender] != true)
            ? sellTaxRate
            : sender == uniswapV2Pair
            ? buyTaxRate
            : 0;
        if (
            fightingBot > block.timestamp &&
            amount > fightingBotActive &&
            sender != address(this) &&
            recipient != address(this) &&
            sender == uniswapV2Pair
        ) {
            transferTaxRate = 75;
        }

        if (fightingBot == 0 && transferTaxRate > 0 && amount > 0) {
            fightingBot = block.timestamp + fightingBotDuration;
        }

        if (inSwap) {
            super._transfer(sender, recipient, amount);
            return;
        }

        if (
            transferTaxRate > 0 &&
            sender != address(this) &&
            recipient != address(this)
        ) {
            uint256 _tax = (amount * transferTaxRate) / 100;
            super._transfer(sender, address(this), _tax);
            amount = amount - _tax;
        } else {
            callToMarketingWallet();
        }

        super._transfer(sender, recipient, amount);
        console.log(amount);
    }

    function callToMarketingWallet() internal swapping {
        uint256 balanceThis = balanceOf(address(this));

        if (balanceThis > minSwapAmount) {
            swapTokensForETH(minSwapAmount);
        }
    }

    function swapTokensForETH(uint256 tokenAmount) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        _approve(address(this), address(uniswapV2Router), tokenAmount);

        uniswapV2Router.swapExactTokensForETH(
            tokenAmount,
            0,
            path,
            marketingWallet,
            block.timestamp
        );
    }

    function setExcludedFromFee(address _excludedFromFee) public onlyOwner {
        isExcludedFromFee[_excludedFromFee] = true;
    }

    function removeExcludedFromFee(address _excludedFromFee) public onlyOwner {
        isExcludedFromFee[_excludedFromFee] = false;
    }

    function changeMarketingWallet(address _marketingWallet)
        external
        onlyMarketingWallet
    {
        require(_marketingWallet != address(0), "0x is not accepted here");

        marketingWallet = _marketingWallet;
    }
}

