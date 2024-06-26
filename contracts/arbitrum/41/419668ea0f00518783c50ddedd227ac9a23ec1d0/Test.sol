// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./ERC20.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./Ownable.sol";
import "./Address.sol";

import "./IUniswapV2Factory.sol";
import "./IUniswapV2Router02.sol";

import "./console.sol";

interface IWETH is IERC20 {
    function deposit() external payable;

    function withdraw(uint256) external;
}

contract Test is ERC20, Ownable {
    using SafeERC20 for IERC20;
    using Address for address payable;

    bool public swapEnabled = true;

    bool public inSwap;
    modifier swapping() {
        inSwap = true;
        _;
        inSwap = false;
    }

    mapping(address => bool) public isFeeExempt;
    mapping(address => bool) public isTxLimitExempt;
    mapping(address => bool) public canAddLiquidityBeforeLaunch;

    uint256 private liquidityFee;
    uint256 private jackpotFee;
    uint256 private marketingFee;
    uint256 private devFee;
    uint256 private totalFee;
    uint256 public feeDenominator = 10000;

    // Buy Fees
    uint256 public liquidityFeeBuy = 100;
    uint256 public jackpotFeeBuy = 500;
    uint256 public marketingFeeBuy = 200;
    uint256 public devFeeBuy = 200;
    uint256 public totalFeeBuy = 1000;
    // Sell Fees
    uint256 public liquidityFeeSell = 100;
    uint256 public jackpotFeeSell = 500;
    uint256 public marketingFeeSell = 200;
    uint256 public devFeeSell = 200;
    uint256 public totalFeeSell = 1000;

    // Fees receivers
    address payable private liquidityIncentiveWallet;
    address payable private marketingWallet;
    address payable public jackpotWallet;
    address payable private devWalletOne;
    address payable private devWalletTwo;

    uint256 public launchedAt;
    uint256 public launchedAtTimestamp;
    bool private initialized;

    IUniswapV2Factory private immutable factory =
        IUniswapV2Factory(0xc35DADB65012eC5796536bD9864eD8773aBc74C4);
    IUniswapV2Router02 private immutable swapRouter =
        IUniswapV2Router02(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506);
    IWETH private immutable WETH =
        IWETH(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    address private constant DEAD = 0x000000000000000000000000000000000000dEaD;
    address private constant ZERO = 0x0000000000000000000000000000000000000000;

    address public pair;

    constructor(
        address _liquidityIncentiveWallet,
        address _marketingWallet,
        address _jackpotWallet,
        address _devWalletOne,
        address _devWalletTwo
    ) ERC20("Test", "TS2") {
        uint256 _totalSupply = 1_000_000 * 1e18;
        liquidityIncentiveWallet = payable(_liquidityIncentiveWallet);
        marketingWallet = payable(_marketingWallet);
        jackpotWallet = payable(_jackpotWallet);
        devWalletOne = payable(_devWalletOne);
        devWalletTwo = payable(_devWalletTwo);
        canAddLiquidityBeforeLaunch[_msgSender()] = true;
        canAddLiquidityBeforeLaunch[address(this)] = true;
        isFeeExempt[msg.sender] = true;
        isTxLimitExempt[msg.sender] = true;
        isFeeExempt[address(this)] = true;
        isTxLimitExempt[address(this)] = true;
        _mint(_msgSender(), _totalSupply);
    }


    function PepeLottoinitializePair() external onlyOwner {
        require(!initialized, "Already initialized");
        pair = factory.createPair(address(WETH), address(this));
        initialized = true;
    }

    receive() external payable {}

    function transfer(
        address to,
        uint256 amount
    ) public virtual override returns (bool) {
        return _lottoTransfer(_msgSender(), to, amount);
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public virtual override returns (bool) {
        address spender = _msgSender();
        _spendAllowance(sender, spender, amount);
        return _lottoTransfer(sender, recipient, amount);
    }

    function _lottoTransfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal returns (bool) {
        if (inSwap) {
            _transfer(sender, recipient, amount);
            return true;
        }
        if (!canAddLiquidityBeforeLaunch[sender]) {
            require(launched(), "Trading not open yet");
        }

        // Set Fees
        if (sender == pair) {
            buyFees();
        }
        if (recipient == pair) {
            sellFees();
        }
        if (shouldSwapBack()) {
            swapBack();
        }
        uint256 amountReceived = shouldTakeFee(sender)
            ? takeFee(sender, amount)
            : amount;
        _transfer(sender, recipient, amountReceived);
        return true;
    }

    // Internal Functions
    function shouldSwapBack() internal view returns (bool) {
        return
            !inSwap &&
            swapEnabled &&
            launched() &&
            balanceOf(address(this)) > 0 &&
            _msgSender() != pair;
    }

    function swapBack() internal swapping {
        uint256 taxAmount = balanceOf(address(this));
        _approve(address(this), address(swapRouter), taxAmount);

        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = address(WETH);

        uint256 balanceBefore = address(this).balance;

        swapRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(
            taxAmount,
            0,
            path,
            address(this),
            block.timestamp
        );

        uint256 amountETH = address(this).balance - balanceBefore;

        uint256 amountETHLiquidity = (amountETH * liquidityFee) / (totalFee);
        uint256 amountETHJackpot = (amountETH * jackpotFee) / totalFee;
        uint256 amountETHMarketing = (amountETH * marketingFee) / totalFee;
        uint256 amountETHDevOne = (amountETH * devFee) / (totalFee * 2);
        uint256 amountETHDevTwo = amountETH -
            amountETHLiquidity -
            amountETHJackpot -
            amountETHMarketing -
            amountETHDevOne;
        liquidityIncentiveWallet.sendValue(amountETHLiquidity);
        jackpotWallet.sendValue(amountETHJackpot);
        marketingWallet.sendValue(amountETHMarketing);
        devWalletOne.sendValue(amountETHDevOne);
        devWalletTwo.sendValue(amountETHDevTwo);
    }

    function launched() internal view returns (bool) {
        return launchedAt != 0;
    }

    function buyFees() internal {
        liquidityFee = liquidityFeeBuy;
        jackpotFee = jackpotFeeBuy;
        marketingFee = marketingFeeBuy;
        devFee = devFeeBuy;
        totalFee = totalFeeBuy;
    }

    function sellFees() internal {
        liquidityFee = liquidityFeeSell;
        jackpotFee = jackpotFeeSell;
        marketingFee = marketingFeeSell;
        devFee = devFeeSell;
        totalFee = totalFeeSell;
    }

    function shouldTakeFee(address sender) internal view returns (bool) {
        return !isFeeExempt[sender] && launched();
    }

    function takeFee(
        address sender,
        uint256 amount
    ) internal returns (uint256) {
        uint256 feeAmount = (amount * totalFee) / feeDenominator;
        _transfer(sender, address(this), feeAmount);
        return amount - feeAmount;
    }

    
    // Stuck Balances Functions
    function rescueToken(address tokenAddress) external onlyOwner {
        IERC20(tokenAddress).safeTransfer(
            msg.sender,
            IERC20(tokenAddress).balanceOf(address(this))
        );
    }

    function clearStuckBalance() external onlyOwner {
        uint256 amountETH = address(this).balance;
        payable(_msgSender()).sendValue(amountETH);
    }

    function getCirculatingSupply() public view returns (uint256) {
        return totalSupply() - balanceOf(DEAD) - balanceOf(ZERO);
    }

    /*** ADMIN FUNCTIONS ***/
    function PepeLottolaunch() public onlyOwner {
        require(launchedAt == 0, "Already launched");
        launchedAt = block.number;
        launchedAtTimestamp = block.timestamp;
    }

    function setBuyFees(
        uint256 _liquidityFee,
        uint256 _jackpotFee,
        uint256 _marketingFee,
        uint256 _devFee
    ) external onlyOwner {
        liquidityFeeBuy = _liquidityFee;
        jackpotFeeBuy = _jackpotFee;
        marketingFeeBuy = _marketingFee;
        devFeeBuy = _devFee;
        totalFeeBuy =
            _liquidityFee +
            (_jackpotFee) +
            (_marketingFee) +
            (_devFee);
    }

    function setSellFees(
        uint256 _liquidityFee,
        uint256 _jackpotFee,
        uint256 _marketingFee,
        uint256 _devFee
    ) external onlyOwner {
        liquidityFeeSell = _liquidityFee;
        jackpotFeeSell = _jackpotFee;
        marketingFeeSell = _marketingFee;
        devFeeSell = _devFee;
        totalFeeSell =
            _liquidityFee +
            (_jackpotFee) +
            (_marketingFee) +
            (_devFee);
    }

    function setFeeReceivers(
        address _liquidityIncentiveWallet,
        address _marketingWallet,
        address _jackpotWallet,
        address _devWalletOne,
        address _devWalletTwo
    ) external onlyOwner {
        liquidityIncentiveWallet = payable(_liquidityIncentiveWallet);
        marketingWallet = payable(_marketingWallet);
        jackpotWallet = payable(_jackpotWallet);
        devWalletOne = payable(_devWalletOne);
        devWalletTwo = payable(_devWalletTwo);
    }

    function setIsFeeExempt(address holder, bool exempt) external onlyOwner {
        isFeeExempt[holder] = exempt;
    } 

    function setSwapBackSettings(bool _enabled) external onlyOwner {
        swapEnabled = _enabled;
    }
}

