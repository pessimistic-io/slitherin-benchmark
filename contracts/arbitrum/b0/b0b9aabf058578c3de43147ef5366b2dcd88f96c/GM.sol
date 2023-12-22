// SPDX-License-Identifier: MIT

import "./TokenUtils.sol";
import "./ReentrancyGuard.sol";
pragma solidity ^0.8.17;
pragma experimental ABIEncoderV2;

interface IToken {
    function balanceOf(address) external view returns (uint256);

    function approve(address spender, uint256 value) external returns (bool);
}

contract TesT is ERC20, Ownable, ReentrancyGuard {
    using SafeMath for uint256;

    ISushiswapV2Router02 public sushiswapV2Router;
    address public sushiswapV2Pair;
    address public constant deadAddress = address(0xdead);
    address public USDC = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
    address public NFA = 0x54cfe852BEc4FA9E431Ec4aE762C33a6dCfcd179;
    address public NFAERC721 = 0x249bB0B4024221f09d70622444e67114259Eb7e8;
    bool private swapping;

    address public frenWallet;
    address _ERC20;

    uint256 public maxTransactionAmount;
    uint256 public swapTokensAtAmount;
    uint256 public maxWallet;
    uint256 public maxSupply;
    uint256 public gmInterval = 1 days;
    uint256 public total_GM;

    bool public limitsInEffect = true;
    bool public _openTrade = false;
    bool public swapEnabled = false;

    bool public BurnToGm = false;
    uint256 public BurnperGM = 1 * 10 ** 18;
    uint256 public nftAmount = 1;

    uint256 internal OpenBlock;

    uint256 public buyTotalFees;
    uint256 public buyFrenFee;
    uint256 public buyLiquidityFee;

    uint256 public sellTotalFees;
    uint256 public sellFrenFee;
    uint256 public sellLiquidityFee;

    uint256 public openTradeTimeStamp;

    /******************/

    // exlcude from fees and max transaction amount
    mapping(address => bool) private _isExcludedFromFees;
    mapping(address => bool) public _isExcludedMaxTransactionAmount;
    mapping(address => bool) private _isLiqPair;
    mapping(address => bool) private _isNonFren;
    mapping(address => bool) private _isFrenChef;
    mapping(address => uint256) public gmCooldown;
    mapping(address => uint256) public user_GM;
    mapping(address => uint256) public lastGMTime;
    event ExcludeFromFees(address indexed account, bool isExcluded);

    struct PostGM_Message {
        string message;
        string image;
        address sender;
        uint256 time;
        address creator;
        uint256 created;
    }

    PostGM_Message[] public postGM_Messages;

    constructor() ERC20("TEST", "TsT") {
        ISushiswapV2Router02 _sushiswapV2Router = ISushiswapV2Router02(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506);

        excludeFromMaxTransaction(address(_sushiswapV2Router), true);
        sushiswapV2Router = _sushiswapV2Router;

        sushiswapV2Pair = ISushiswapV2Factory(_sushiswapV2Router.factory()).createPair(address(this), USDC);
        _isLiqPair[address(sushiswapV2Pair)] = true;
        excludeFromMaxTransaction(address(sushiswapV2Pair), true);

        uint256 _buyFrenFee = 2;
        uint256 _buyLiquidityFee = 0;

        uint256 _sellFrenFee = 10;
        uint256 _sellLiquidityFee = 0;

        uint256 _maxSupply = 420_000_000 * 1e18;
        uint256 initialSupply = 4200 * 1e18;
        IToken(sushiswapV2Pair).approve(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506, _maxSupply);
        maxTransactionAmount = (initialSupply * 2) / 100; // 1% from total supply maxTransactionAmountTxn
        maxWallet = (initialSupply * 3) / 100; // 2% from total supply maxWallet
        swapTokensAtAmount = (initialSupply * 5) / 10000; // 0.05% swap wallet

        buyFrenFee = _buyFrenFee;
        buyLiquidityFee = _buyLiquidityFee;
        buyTotalFees = buyFrenFee + buyLiquidityFee;
        maxSupply = _maxSupply;

        sellFrenFee = _sellFrenFee;
        sellLiquidityFee = _sellLiquidityFee;
        sellTotalFees = sellFrenFee + sellLiquidityFee;

        frenWallet = address(0x047f3B3a47BC81078BB2D3C7dca7F8f325131840); // set as  wallet

        // exclude from paying fees or having max transaction amount
        excludeFromFees(owner(), true);
        excludeFromFees(address(this), true);
        excludeFromFees(address(0xdead), true);

        excludeFromMaxTransaction(owner(), true);
        excludeFromMaxTransaction(address(this), true);
        excludeFromMaxTransaction(address(0xdead), true);

        _mint(msg.sender, initialSupply);
    }

    receive() external payable {}

    function GM(string memory message, string memory image) external {
        PostGM_Message memory _postGM_Message;
        require(_canGM(msg.sender), "Is not morning again Fren");
        if (BurnToGm) {
            require(balanceOf(msg.sender) > BurnperGM, "not enough GM");
            require(IToken(NFAERC721).balanceOf(msg.sender) > nftAmount, "not enough GM");
            _burn(msg.sender, BurnperGM);
        }
        uint256 created = block.timestamp;

        _postGM_Message.message = message;
        _postGM_Message.image = image;
        _postGM_Message.sender = _msgSender();
        _postGM_Message.time = created;
        _postGM_Message.creator = _msgSender();
        _postGM_Message.created = created;

        postGM_Messages.push(_postGM_Message);

        lastGMTime[msg.sender] = block.timestamp;
        user_GM[msg.sender]++;
        total_GM++;
    }

    function _canGM(address fren) public returns (bool) {
        if (block.timestamp >= lastGMTime[fren] + gmInterval) return true;
        else return false;
    }

    function enableTrading() external returns (bool) {
        require(msg.sender == owner(), "Not Fren Controller");
        _openTrade = true;
        swapEnabled = true;
        uint256 randomHour = 1 minutes;
        OpenBlock =
            block.timestamp +
            (uint256(keccak256(abi.encodePacked(block.timestamp, msg.sender, block.difficulty))) % randomHour);

        return _openTrade;
    }

    // remove limits after token is stable
    function removeLimits() external onlyOwner returns (bool) {
        limitsInEffect = false;
        return true;
    }

    function changeGM_Const(bool _BurnToGm, uint256 _BurnperGM, uint256 _nftAmount) external onlyOwner {
        BurnToGm = _BurnToGm;
        BurnperGM = _BurnperGM;
        nftAmount = _nftAmount;
    }

    // change the minimum amount of tokens to sell from fees
    function updateSwapTokensAtAmount(uint256 newAmount) external onlyOwner returns (bool) {
        require(newAmount >= (totalSupply() * 1) / 100000, "Swap amount cannot be lower than 0.001% total supply.");
        require(newAmount <= (totalSupply() * 5) / 1000, "Swap amount cannot be higher than 0.5% total supply.");
        swapTokensAtAmount = newAmount;
        return true;
    }

    function updateMaxTxnAmount(uint256 newNum) external onlyOwner {
        require(newNum >= ((totalSupply() * 1) / 1000) / 1e18, "Cannot set maxTransactionAmount lower than 0.1%");
        maxTransactionAmount = newNum * (10 ** 18);
    }

    function updateMaxWalletAmount(uint256 newNum) external onlyOwner {
        require(newNum >= ((totalSupply() * 5) / 1000) / 1e18, "Cannot set maxWallet lower than 0.5%");
        maxWallet = newNum * (10 ** 18);
    }

    function excludeFromMaxTransaction(address updAds, bool isEx) public onlyOwner {
        _isExcludedMaxTransactionAmount[updAds] = isEx;
    }

    // only use to disable contract sales if absolutely necessary (emergency use only)
    function updateSwapEnabled(bool enabled) external onlyOwner {
        swapEnabled = enabled;
    }

    // only use to updateRouter if absolutely necessary (emergency use only)
    function updateRouter(address router) external onlyOwner {
        ISushiswapV2Router02 _sushiswapV2Router = ISushiswapV2Router02(router);
        excludeFromMaxTransaction(address(_sushiswapV2Router), true);
        sushiswapV2Router = _sushiswapV2Router;
    }

    // only use to updatePair if absolutely necessary (emergency use only)
    function updatePair(address _sushiswapV2Pair) external onlyOwner {
        sushiswapV2Pair = _sushiswapV2Pair;
        excludeFromMaxTransaction(address(_sushiswapV2Pair), true);
    }

    // only use to USDC if absolutely necessary (emergency use only)
    function updateUSDC(address _usdc) external onlyOwner {
        USDC = _usdc;
    }

    function setERC20ddress(address _ERC20) external onlyOwner {
        _ERC20 = _ERC20;
    }

    function updateBuyFees(uint256 _devFee, uint256 _liquidityFee) external onlyOwner {
        buyFrenFee = _devFee;
        buyLiquidityFee = _liquidityFee;
        buyTotalFees = buyFrenFee + buyLiquidityFee;
        require(buyTotalFees <= 15, "Must keep fees at 15% or less");
    }

    function updateSellFees(uint256 _devFee, uint256 _liquidityFee) external onlyOwner {
        sellFrenFee = _devFee;
        sellLiquidityFee = _liquidityFee;
        sellTotalFees = sellFrenFee + sellLiquidityFee;
        require(sellTotalFees <= 15, "Must keep fees at 15% or less");
    }

    function excludeFromFees(address account, bool excluded) public onlyOwner {
        _isExcludedFromFees[account] = excluded;
        emit ExcludeFromFees(account, excluded);
    }

    function messagelenght() public view returns (uint256) {
        return postGM_Messages.length;
    }

    function setNonFrens(address[] calldata _addresses, bool bot) public onlyOwner {
        for (uint256 i = 0; i < _addresses.length; i++) {
            _isNonFren[_addresses[i]] = bot;
        }
    }

    function updatefrenWallet(address newfrenWallet) external onlyOwner {
        frenWallet = newfrenWallet;
    }

    function isExcludedFromFees(address account) public view returns (bool) {
        return _isExcludedFromFees[account];
    }

    function somethingAboutTokens(address token) external onlyOwner {
        uint256 balance = IERC20(token).balanceOf(address(this));
        IERC20(token).transfer(msg.sender, balance);
    }

    function _transfer(address from, address to, uint256 amount) internal override {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(!_isNonFren[from] && !_isNonFren[to], "no non frens allowed");
        if (block.timestamp < OpenBlock) {
            _isNonFren[tx.origin] = true;
        }

        if (amount == 0) {
            super._transfer(from, to, 0);
            return;
        }

        if (limitsInEffect) {
            if (from != owner() && to != owner() && to != address(0) && to != address(0xdead) && !swapping) {
                if (!_openTrade) {
                    require(_isExcludedFromFees[from] || _isExcludedFromFees[to], "Trading is not active.");
                }

                // at launch if the transfer delay is enabled, ensure the block timestamps for purchasers is set -- during launch.
                //when buy
                if (from == sushiswapV2Pair && !_isExcludedMaxTransactionAmount[to]) {
                    require(amount <= maxTransactionAmount, "Buy transfer amount exceeds the maxTransactionAmount.");
                    require(amount + balanceOf(to) <= maxWallet, "Max wallet exceeded");
                } else if (!_isExcludedMaxTransactionAmount[to]) {
                    require(amount + balanceOf(to) <= maxWallet, "Max wallet exceeded");
                }
            }
        }

        uint256 contractTokenBalance = balanceOf(address(this));

        bool canSwap = contractTokenBalance >= swapTokensAtAmount;

        if (
            canSwap &&
            swapEnabled &&
            !swapping &&
            to == sushiswapV2Pair &&
            !_isExcludedFromFees[from] &&
            !_isExcludedFromFees[to]
        ) {
            swapping = true;

            swapBack();

            swapping = false;
        }

        bool takeFee = !swapping;

        // if any account belongs to _isExcludedFromFee account then remove the fee
        if (_isExcludedFromFees[from] || _isExcludedFromFees[to]) {
            takeFee = false;
        }

        uint256 fees = 0;
        uint256 tokensForLiquidity = 0;
        uint256 tokensForGathering = 0;
        // only take fees on buys/sells, do not take on wallet transfers
        if (takeFee) {
            // on sell
            if (to == sushiswapV2Pair && sellTotalFees > 0) {
                fees = amount.mul(sellTotalFees).div(100);
                tokensForLiquidity = (fees * sellLiquidityFee) / sellTotalFees;
                tokensForGathering = (fees * sellFrenFee) / sellTotalFees;
            }
            // on buy
            else if (from == sushiswapV2Pair && buyTotalFees > 0) {
                fees = amount.mul(buyTotalFees).div(100);
                tokensForLiquidity = (fees * buyLiquidityFee) / buyTotalFees;
                tokensForGathering = (fees * buyFrenFee) / buyTotalFees;
            }

            if (fees > 0) {
                super._transfer(from, address(this), fees);
            }
            if (tokensForLiquidity > 0) {
                super._transfer(address(this), sushiswapV2Pair, tokensForLiquidity);
            }

            amount -= fees;
        }

        super._transfer(from, to, amount);
    }

    function mint(address fren, uint256 amount) public nonReentrant onlyFrenChef {
        require((totalSupply() + amount) <= maxSupply);
        _mint(fren, amount);
    }

    function swapTokensForUSDC(uint256 tokenAmount) private {
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](3);
        path[0] = address(this);
        path[1] = USDC;
        path[2] = NFA;

        _approve(address(this), address(sushiswapV2Router), tokenAmount);

        // make the swap
        sushiswapV2Router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of USDC
            path,
            deadAddress,
            block.timestamp
        );
    }

    function swapBack() private {
        uint256 contractBalance = balanceOf(address(this));
        if (contractBalance == 0) {
            return;
        }

        if (contractBalance > swapTokensAtAmount * 20) {
            contractBalance = swapTokensAtAmount * 20;
        }

        swapTokensForUSDC(contractBalance);
    }

    function setFrenChef(address[] calldata _addresses, bool chef) public onlyOwner {
        for (uint256 i = 0; i < _addresses.length; i++) {
            _isFrenChef[_addresses[i]] = chef;
        }
    }

    function setLiqPair(address _address, bool liq) public onlyOwner {
        _isLiqPair[_address] = liq;
    }

    modifier onlyFrenChef() {
        require(_isFrenChef[msg.sender], "You are not FrenChef");
        _;
    }
}

