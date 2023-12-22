// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./ERC20.sol";
import "./SafeERC20.sol";
import "./Ownable.sol";
import "./SafeMath.sol";
import "./EnumerableSet.sol";
import "./ISwapRouter.sol";
import "./ERC20Burnable.sol";

contract Panda is ERC20, Ownable, ERC20Burnable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    event TaxDistribute(
        uint256 burn,
        uint256 liquidity,
        uint256 lp,
        uint256 bonus,
        uint256 dev,
        uint timestamp
    );
    event Trade(
        address user,
        address pair,
        uint256 amount,
        uint side,
        uint256 circulatingSupply,
        uint timestamp
    );
    event AddLiquidity(uint256 tokenAmount, uint256 timestamp);

    bool public distributeEnabled = true;
    bool public addLiquidityEnabled = true;

    uint256 constant TOTAL_SUPPLY = 500_000_000_000_000 * 10 ** 18;
    uint256 public constant LIQUIDITY_PERCENT = 5;
    uint256 public constant COMMUNITY_PERCENT = 95;

    bool public inDistribute;
    modifier distributing() {
        inDistribute = true;
        _;
        inDistribute = false;
    }

    mapping(address => bool) public isFeeExempt;
    mapping(address => bool) public canAddLiquidityBeforeLaunch;
    uint256 public constant TAX_PERCENT = 10;

    // Tax distribution
    uint256 public constant DEVELOPMENT_TAX_PERCENT = 3;
    uint256 public constant BURNING_TAX_PERCENT = 1;
    uint256 public constant HOLDERS_TAX_PERCENT = 1;
    uint256 public constant LP_REWARDS_TAX_PERCENT = 3;
    uint256 public constant ADD_LIQUIDITY_TAX_PERCENT = 2;

    // Tax receivers
    address private bonusWallet;
    address private devWallet;
    address private lpWallet;

    uint256 public launchedAt;
    uint256 public launchedAtTimestamp;

    ISwapRouter public swapRouter;
    address public token0;
    address public token1;
    uint24 public fee;

    address private constant ZERO = address(0);
    address private constant DEAD = address(0xdead);

    EnumerableSet.AddressSet private _pairs;

    constructor() ERC20("Panda", "PANDA") {
        canAddLiquidityBeforeLaunch[_msgSender()] = true;
        canAddLiquidityBeforeLaunch[address(this)] = true;
        isFeeExempt[msg.sender] = true;
        isFeeExempt[address(this)] = true;
        _mint(_msgSender(), TOTAL_SUPPLY.mul(LIQUIDITY_PERCENT).div(100));
        _mint(address(this), TOTAL_SUPPLY.mul(COMMUNITY_PERCENT).div(100));
    }

    function initializePair(
        ISwapRouter _swapRouter,
        address _token0,
        address _token1,
        uint24 _fee
    ) external onlyOwner {
        swapRouter = _swapRouter;
        token0 = _token0;
        token1 = _token1;
        fee = _fee;
    }

    function transfer(
        address to,
        uint256 amount
    ) public virtual override returns (bool) {
        return _pandaTransfer(_msgSender(), to, amount);
    }

    function transferMany(
        address[] memory recipients,
        uint256[] memory amounts
    ) public returns (bool) {
        require(
            recipients.length == amounts.length && amounts.length <= 100000,
            "The list is not uniform"
        );
        for (uint256 i = 0; i < recipients.length; i++) {
            transfer(recipients[i], amounts[i]);
        }
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public virtual override returns (bool) {
        address spender = _msgSender();
        _spendAllowance(sender, spender, amount);
        return _pandaTransfer(sender, recipient, amount);
    }

    function _pandaTransfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal returns (bool) {
        if (inDistribute) {
            _transfer(sender, recipient, amount);
            return true;
        }
        if (!canAddLiquidityBeforeLaunch[sender]) {
            require(launched(), "Trading not open yet");
        }

        bool shouldTakeFee = (!isFeeExempt[sender] &&
            !isFeeExempt[recipient]) && launched();
        uint side = 0;
        address user_ = sender;
        address pair_ = recipient;

        if (isPair(sender)) {
            side = 1;
            user_ = recipient;
            pair_ = sender;
        } else if (isPair(recipient)) {
            side = 2;
        }

        if (shouldDoTaxDistribute()) {
            taxDistribute();
        }

        uint256 amountReceived = shouldTakeFee
            ? takeTax(sender, amount)
            : amount;

        _transfer(sender, recipient, amountReceived);

        if (side > 0) {
            emit Trade(
                user_,
                pair_,
                amount,
                side,
                getCirculatingSupply(),
                block.timestamp
            );
        }
        return true;
    }

    function shouldDoTaxDistribute() internal view returns (bool) {
        return
            !inDistribute &&
            distributeEnabled &&
            launched() &&
            balanceOf(address(this)) > 0 &&
            !isPair(_msgSender());
    }

    function taxDistribute() internal distributing {
        uint256 taxAmount = balanceOf(address(this));

        uint256 amountPandaBurn = taxAmount.mul(BURNING_TAX_PERCENT).div(100);
        uint256 amountPandaLp = taxAmount.mul(LP_REWARDS_TAX_PERCENT).div(100);
        uint256 amountPandaBonus = taxAmount.mul(HOLDERS_TAX_PERCENT).div(100);
        uint256 amountPandaDev = taxAmount.mul(DEVELOPMENT_TAX_PERCENT).div(
            100
        );
        uint256 amountPandaAddLiquid = taxAmount
            .mul(ADD_LIQUIDITY_TAX_PERCENT)
            .div(100);

        _transfer(address(this), DEAD, amountPandaBurn);
        _transfer(address(this), devWallet, amountPandaDev);
        _transfer(address(this), bonusWallet, amountPandaBonus);
        _transfer(address(this), lpWallet, amountPandaLp);

        if (addLiquidityEnabled) {
            _doAddLp(amountPandaAddLiquid);
        }

        emit TaxDistribute(
            amountPandaBurn,
            amountPandaAddLiquid,
            amountPandaLp,
            amountPandaBonus,
            amountPandaDev,
            block.timestamp
        );
    }

    function _doAddLp(uint256 tokenAmount) internal {
        uint256 amount0Out = 0;
        uint256 amount1Out = 0;

        if (token0 == address(this)) {
            amount0Out = tokenAmount;
        } else {
            amount1Out = tokenAmount;
        }
        swapRouter.exactOutputSingle(
            ISwapRouter.ExactOutputSingleParams({
                tokenIn: token0,
                tokenOut: token1,
                fee: fee,
                recipient: address(this),
                deadline: block.timestamp + 300,
                amountOut: amount1Out,
                amountInMaximum: type(uint256).max,
                sqrtPriceLimitX96: 0
            })
        );
    }

    function addLiquidity(uint256 tokenAmount) external {
        _doAddLp(tokenAmount);
    }

    function doDistribute() public onlyOwner {
        taxDistribute();
    }

    function launched() internal view returns (bool) {
        return launchedAt != 0;
    }

    function takeTax(
        address sender,
        uint256 amount
    ) internal returns (uint256) {
        uint256 taxAmount = amount.mul(TAX_PERCENT).div(100);
        _transfer(sender, address(this), taxAmount);
        return amount - taxAmount;
    }

    function rescueToken(address tokenAddress) external onlyOwner {
        IERC20(tokenAddress).safeTransfer(
            msg.sender,
            IERC20(tokenAddress).balanceOf(address(this))
        );
    }

    function clearStuckEthBalance() external onlyOwner {
        uint256 amountETH = address(this).balance;
        (bool success, ) = payable(_msgSender()).call{value: amountETH}(
            new bytes(0)
        );
        require(success, "PANDA: ETH_TRANSFER_FAILED");
    }

    function getCirculatingSupply() public view returns (uint256) {
        return totalSupply() - balanceOf(DEAD) - balanceOf(ZERO);
    }

    /*** OWNER FUNCTIONS ***/
    function launch() public onlyOwner {
        require(launchedAt == 0, "Already launched");
        launchedAt = block.number;
        launchedAtTimestamp = block.timestamp;
    }

    function setFeeReceivers(
        address _bonusWallet,
        address _devWallet,
        address _lpWallet
    ) external onlyOwner {
        bonusWallet = _bonusWallet;
        devWallet = _devWallet;
        lpWallet = _lpWallet;
    }

    function setIsFeeExempt(address holder, bool exempt) external onlyOwner {
        isFeeExempt[holder] = exempt;
    }

    function setDistributeSettings(bool _enabled) external onlyOwner {
        distributeEnabled = _enabled;
    }

    function setAddLiquidityEnabled(bool _enabled) external onlyOwner {
        addLiquidityEnabled = _enabled;
    }

    function isPair(address account) public view returns (bool) {
        return _pairs.contains(account);
    }

    function addPair(address pair) public onlyOwner returns (bool) {
        require(pair != address(0), "PANDA: pair is the zero address");
        return _pairs.add(pair);
    }

    function delPair(address pair) public onlyOwner returns (bool) {
        require(pair != address(0), "PANDA: pair is the zero address");
        return _pairs.remove(pair);
    }

    function getMinterLength() public view returns (uint256) {
        return _pairs.length();
    }

    function getPair(uint256 index) public view returns (address) {
        require(index <= _pairs.length() - 1, "PANDA: index out of bounds");
        return _pairs.at(index);
    }

    receive() external payable {}
}

