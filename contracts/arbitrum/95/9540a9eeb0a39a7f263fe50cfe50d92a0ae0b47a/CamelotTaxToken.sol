
// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "./CamelotUtils.sol";

import "./SafeMath.sol";
import "./Ownable.sol";
import "./ERC20.sol";
import "./SafeERC20.sol";

interface IWETH is IERC20 {
    function deposit() external payable;
    function withdraw(uint256) external;
}

contract PokuCamelot is ERC20, Ownable {
    using SafeERC20 for IERC20;
    using Address for address payable;

    uint256 public maxTxAmount;
    uint256 public maxWallet;
    bool public swapEnabled = true;

    bool public inSwap;
    modifier swapping() {
        inSwap = true;
        _;
        inSwap = false;
    }

    mapping(address => bool) public isFeeExempt;
    mapping(address => bool) public isTxLimitExempt;
    mapping(address => bool) public isWalletLimitExempt;
    mapping(address => bool) public canAddLiquidityBeforeLaunch;
    mapping(address => bool) blacklisted;

    uint256 private swapBackAtAmount;

    uint256 private liquidityFee;
    uint256 private devFee;
    uint256 private totalFee;
    uint256 public feeDenominator = 10000;

    // Buy Fees
    uint256 public liquidityFeeBuy = 0;
    uint256 public devFeeBuy = 500;
    uint256 public totalFeeBuy = 500;
    // Sell Fees
    uint256 public liquidityFeeSell = 0;
    uint256 public devFeeSell = 500;
    uint256 public totalFeeSell = 500;

    // Fees receivers
    address payable private liquidityWallet;
    address payable private devWallet;

    uint256 public launchedAt;

    ICamelotFactory private immutable factory = ICamelotFactory(0x6EcCab422D763aC031210895C81787E87B43A652);
    ICamelotRouter private immutable swapRouter = ICamelotRouter(0xc873fEcbd354f5A56E00E710B90EF4201db2448d);
    IWETH private immutable WETH = IWETH(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    address private constant DEAD = 0x000000000000000000000000000000000000dEaD;
    address private constant ZERO = 0x0000000000000000000000000000000000000000;

    address public pair;

    constructor() ERC20("Poku Test", "POKU") {
        uint256 _totalSupply = 1_000_000_000 * 1e18;
        maxTxAmount = (_totalSupply * 2) / 100; //2%
        maxWallet = (_totalSupply * 2) / 100; //2%
        swapBackAtAmount = 1000 * 1e18;
        devWallet = payable(address(0x849e291e07d650B862f81160ed2b4463029E9E0E));
        liquidityWallet = devWallet;

        canAddLiquidityBeforeLaunch[_msgSender()] = true;
        canAddLiquidityBeforeLaunch[address(this)] = true;
        isFeeExempt[msg.sender] = true;
        isTxLimitExempt[msg.sender] = true;
        isWalletLimitExempt[msg.sender] = true;
        isFeeExempt[address(this)] = true;
        isTxLimitExempt[address(this)] = true;
        isWalletLimitExempt[address(this)] = true;

        _mint(_msgSender(), _totalSupply);
    }

    receive() external payable {}

    function createPair() external onlyOwner {
        require(pair == address(0), "Pair already created");
        pair = factory.createPair(address(WETH), address(this));
    }

    function transfer(
        address to,
        uint256 amount
    ) public virtual override returns (bool) {
        return _brainTransfer(_msgSender(), to, amount);
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public virtual override returns (bool) {
        address spender = _msgSender();
        _spendAllowance(sender, spender, amount);
        return _brainTransfer(sender, recipient, amount);
    }

    function _brainTransfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal returns (bool) {
        require(!blacklisted[sender],"Sender blacklisted");
        require(!blacklisted[recipient],"Receiver blacklisted");

        if (inSwap) {
            _transfer(sender, recipient, amount);
            return true;
        }
        if (!canAddLiquidityBeforeLaunch[sender]) {
            require(launched(), "Trading not open yet");
        }

        checkWalletLimit(recipient, amount);
        checkTxLimit(sender, amount);

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
            balanceOf(address(this)) > swapBackAtAmount &&
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
            address(0),
            block.timestamp
        );

        uint256 amountETH = address(this).balance - balanceBefore;

        uint256 amountETHLiquidity = (amountETH * liquidityFee) / (totalFee);
        uint256 amountETHDev = amountETH - amountETHLiquidity;
        liquidityWallet.sendValue(amountETHLiquidity);
        devWallet.sendValue(amountETHDev);
    }

    function launched() internal view returns (bool) {
        return launchedAt != 0;
    }

    function buyFees() internal {
        liquidityFee = liquidityFeeBuy;
        devFee = devFeeBuy;
        totalFee = totalFeeBuy;
    }

    function sellFees() internal {
        liquidityFee = liquidityFeeSell;
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

    function checkWalletLimit(address recipient, uint256 amount) internal view {
        if (
            recipient != owner() &&
            recipient != address(this) &&
            recipient != address(DEAD) &&
            recipient != pair
        ) {
            uint256 heldTokens = balanceOf(recipient);
            require(
                (heldTokens + amount) <= maxWallet || isWalletLimitExempt[recipient],
                "Total Holding is currently limited, you can not buy that much."
            );
        }
    }

    function checkTxLimit(address sender, uint256 amount) internal view {
        require(
            amount <= maxTxAmount || isTxLimitExempt[sender],
            "TX Limit Exceeded"
        );
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
    function launch() public onlyOwner {
        require(launchedAt == 0, "Already launched");
        launchedAt = block.number;
    }

    // change the minimum amount of tokens to sell from fees
    function updateSwapBackAtAmount(uint256 newAmount)
        external
        onlyOwner
        returns (bool)
    {
        swapBackAtAmount = newAmount * 1e18;
        return true;
    }

    function showSwapBackAtAmount() public view returns(uint256) {
        return swapBackAtAmount / 1e18;
    }

    function setBuyFees(
        uint256 _liquidityFee,
        uint256 _devFee
    ) external onlyOwner {
        liquidityFeeBuy = _liquidityFee;
        devFeeBuy = _devFee;
        totalFeeBuy =
            _liquidityFee +
            _devFee;
    }

    function setSellFees(
        uint256 _liquidityFee,
        uint256 _devFee
    ) external onlyOwner {
        liquidityFeeSell = _liquidityFee;
        devFeeSell = _devFee;
        totalFeeSell =
            _liquidityFee +
            _devFee;
    }

    function setFeeReceivers(
        address _liquidityWallet,
        address _devWallet
    ) external onlyOwner {
        liquidityWallet = payable(_liquidityWallet);
        devWallet = payable(_devWallet);
    }

    function setMaxWallet(uint256 amount) external onlyOwner {
        maxWallet = amount;
    }

    function setTxLimit(uint256 amount) external onlyOwner {
        maxTxAmount = amount;
    }

    function setIsFeeExempt(address holder, bool exempt) external onlyOwner {
        isFeeExempt[holder] = exempt;
    }

    function setIsTxLimitExempt(
        address holder,
        bool exempt
    ) external onlyOwner {
        isTxLimitExempt[holder] = exempt;
    }

    function setIsWalletLimitExempt(
        address holder,
        bool exempt
    ) external onlyOwner {
        isWalletLimitExempt[holder] = exempt;
    }

    function setSwapBackSettings(bool _enabled) external onlyOwner {
        swapEnabled = _enabled;
    }

    function blacklist(address _black) public onlyOwner {
        blacklisted[_black] = true;
    }

    function unblacklist(address _black) public onlyOwner {
        blacklisted[_black] = false;
    }

    function isBlacklisted(address account) public view returns (bool) {
        return blacklisted[account];
    }
}

