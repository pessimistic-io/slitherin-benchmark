// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./ERC20.sol";
import "./SafeERC20.sol";
import "./Ownable.sol";
import "./SafeMath.sol";
import "./EnumerableSet.sol";
import "./IWETH.sol";
import "./IUniswapV2Router02.sol";
import "./IUniswapV2Factory.sol";
import "./IPandaBonusPool.sol";
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
    event AddLiquidity(
        uint256 tokenAmount,
        uint256 ethAmount,
        uint256 timestamp
    );
    event Claim(uint256 tokenAmount, address to, uint256 timestamp);

    bool public distributeEnabled = true;
    bool public addLiquidityEnabled = true;

    mapping(address => uint256) public claimed;
    uint256 constant TOTAL_SUPPLY = 500_000_000_000_000 * 10 ** 18;
    uint256 public constant LIQUIDITY_PERCENT = 5;
    uint256 public constant COMMUNITY_PERCENT = 95;
    uint256 public constant tokenPerAddressMin = 1_500_000_000 * 10 ** 18;
    uint256 public constant tokenPerAddressMax = 1_600_000_000 * 10 ** 18;

    uint256 public startTime;
    uint256 public endTime;
    address[] public arbAddresses;

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
    bool private initialized;

    IUniswapV2Factory private immutable factory;
    IUniswapV2Router02 private immutable swapRouter;
    IWETH private immutable WETH;
    address private constant DEAD = address(0xdead);
    address private constant ZERO = address(0);

    EnumerableSet.AddressSet private _pairs;

    constructor(
        address _factory,
        address _swapRouter,
        address _weth
    ) ERC20("Panda", "PANDA") {
        canAddLiquidityBeforeLaunch[_msgSender()] = true;
        canAddLiquidityBeforeLaunch[address(this)] = true;
        isFeeExempt[msg.sender] = true;
        isFeeExempt[address(this)] = true;
        factory = IUniswapV2Factory(_factory);
        swapRouter = IUniswapV2Router02(_swapRouter);
        WETH = IWETH(_weth);
        _mint(_msgSender(), TOTAL_SUPPLY.mul(LIQUIDITY_PERCENT).div(100));
        _mint(address(this), TOTAL_SUPPLY.mul(COMMUNITY_PERCENT).div(100));
    }

    function initializePair() external onlyOwner {
        require(!initialized, "Already initialized");
        address pair = factory.createPair(address(WETH), address(this));
        _pairs.add(pair);
        initialized = true;
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
        address[] memory pathEth = new address[](2);
        pathEth[0] = address(this);
        pathEth[1] = address(WETH);

        uint256 half = tokenAmount / 2;
        if (half < 1000) return;

        uint256 ethAmountBefore = address(this).balance;
        bool success = false;
        try
            swapRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(
                half,
                0,
                pathEth,
                address(this),
                block.timestamp
            )
        {
            success = true;
        } catch {
            try
                swapRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(
                    half,
                    0,
                    pathEth,
                    address(this),
                    block.timestamp
                )
            {
                success = true;
            } catch {}
        }
        if (!success) {
            return;
        }

        uint256 ethAmount = address(this).balance - ethAmountBefore;
        _addLiquidity(half, ethAmount);
    }

    function _addLiquidity(uint256 tokenAmount, uint256 ethAmount) internal {
        _approve(address(this), address(swapRouter), tokenAmount);
        try
            swapRouter.addLiquidityETH{value: ethAmount}(
                address(this),
                tokenAmount,
                0,
                0,
                address(0),
                block.timestamp
            )
        {
            emit AddLiquidity(tokenAmount, ethAmount, block.timestamp);
        } catch {}
    }

    function doDistribute() public onlyOwner {
        taxDistribute();
    }

    function random(uint256 min, uint256 max) internal view returns (uint256) {
        uint256 blockNumber = block.number - 1;
        uint256 blockHash = uint256(blockhash(blockNumber));
        uint256 randomNum = uint256(
            keccak256(abi.encodePacked(blockHash, block.timestamp))
        );
        return (randomNum % (max - min + 1)) + min;
    }

    function claimTokens() external {
        require(
            block.timestamp >= startTime && block.timestamp < endTime,
            "Claiming period has not started or has ended."
        );
        require(
            claimed[msg.sender] == 0,
            "You have already claimed your tokens."
        );
        require(isWhitelisted(msg.sender), "You are not in whitelist.");
        uint256 rewardRemain = balanceOf(address(this));
        uint256 tokenAmount = random(tokenPerAddressMin, tokenPerAddressMax);
        require(
            rewardRemain >= tokenAmount,
            "out of reward tokens"
        );

        claimed[msg.sender] = tokenAmount;
        _transfer(address(this), msg.sender, tokenAmount);
        emit Claim(tokenAmount, msg.sender, block.timestamp);
    }

    function launched() internal view returns (bool) {
        return launchedAt != 0;
    }

    function addWhitelist(address[] memory _whitelist) external onlyOwner {
        for (uint i = 0; i < _whitelist.length; i++) {
            address _address = _whitelist[i];
            require(!isWhitelisted(_address), "Address is already whitelisted");
            arbAddresses.push(_address);
        }
    }

    function isWhitelisted(address _address) public view returns (bool) {
        for (uint i = 0; i < arbAddresses.length; i++) {
            if (arbAddresses[i] == _address) {
                return true;
            }
        }
        return false;
    }

    function removeAddress(address _address) public {
        require(isWhitelisted(_address), "Address is not in whitelist");
        for (uint i = 0; i < arbAddresses.length; i++) {
            if (arbAddresses[i] == _address) {
                arbAddresses[i] = arbAddresses[arbAddresses.length - 1];
                arbAddresses.pop();
                break;
            }
        }
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

    function setClaimTime(
        uint256 _startTime,
        uint256 _endTime
    ) external onlyOwner {
        startTime = _startTime;
        endTime = _endTime;
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

