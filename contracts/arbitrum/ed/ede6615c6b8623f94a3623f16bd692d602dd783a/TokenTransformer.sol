// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

import { Initializable } from "./Initializable.sol";
import { ReentrancyGuardUpgradeable } from "./ReentrancyGuardUpgradeable.sol";
import { OwnableUpgradeable } from "./OwnableUpgradeable.sol";
import { IERC20Upgradeable } from "./IERC20Upgradeable.sol";
import { SafeERC20Upgradeable } from "./SafeERC20Upgradeable.sol";
// import { IERC721ReceiverUpgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721ReceiverUpgradeable.sol";

import { IWETH } from "./IWETH.sol";
import { ISwapRouter } from "./ISwapRouter.sol";
import { INonfungiblePositionManager } from "./INonfungiblePositionManager.sol";
import { IAllowlist } from "./IAllowlist.sol";

contract TokenTransformer is Initializable, ReentrancyGuardUpgradeable, OwnableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    uint256 private constant PRECISION = 1e18;
    uint128 private constant TOTAL_SALE = 3000000e18;
    uint128 private constant TOKEN_MINT_AMOUNTS = 800000e18;
    uint128 private constant WETH_MINT_PERCENT = 2666e14;
    uint128 private constant MIN_INVEST_AMOUNTS = 0.1 ether;
    int24 public constant TICK_LOWER = -887220;
    int24 public constant TICK_UPPER = -TICK_LOWER;

    address public nonfungiblePositionManager;
    address public swapRouter;
    address public wethAddress;
    address public archiToken;
    address public allowlist;

    uint256 public hardcap;
    uint256 public startedAt;
    uint256 public finishedAt;

    struct Global {
        uint256 totalUsers;
        uint256 totalWeiContributed;
        uint256 liquidity;
        address token0;
        address token1;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0;
        uint256 amount1;
        uint256 tokenId;
        uint24 poolFee;
    }

    Global public g;

    mapping(address => bool) public supportedTokens;
    mapping(address => uint256) public balanceOf;
    mapping(address => uint256[2]) public claimed;
    mapping(address => uint24) public feeTiers;

    event Buy(address indexed sender, address _token, uint256 _amountIn, uint256 _refundAmount, uint256 _amountOut);
    event Claim(address indexed _recipient, uint256 _vestingAmount, uint256 _claimAmount);
    event UpdateSupportedToken(address indexed _token, bool _state);
    event UpdateFeeTier(address indexed _token, uint24 _feeTier);
    event UniswapResult(uint256 _tokenId, uint256 _liquidity, uint256 _amount0, uint256 _amount1);

    modifier onlyStarted() {
        require(block.timestamp >= startedAt, "TokenTransformer: Contract has not started yet");
        require(block.timestamp <= finishedAt, "TokenTransformer: IDO has ended");
        _;
    }

    modifier onlyFinished() {
        require(block.timestamp > finishedAt, "TokenTransformer: Contract has not finished yet");
        _;
    }

    modifier afterUniswapTransfer() {
        require(g.tokenId > 0, "TokenTransformer: Please wait until liquidity is added");
        _;
    }

    modifier beforeUniswapTransfer() {
        require(g.tokenId == 0, "TokenTransformer: Already added liquidity");
        _;
    }

    modifier onlyEligible(address _recipient) {
        require(balanceOf[_recipient] > 0, "TokenTransformer: You have not participated in IDO yet");
        _;
    }

    modifier onlyAllowlist(address _recipient) {
        if (allowlist != address(0)) {
            if (block.timestamp <= startedAt + 1 days) {
                bool passed = IAllowlist(allowlist).can(_recipient);

                require(passed, "TokenTransformer: Not whitelisted");
            }
        }
        _;
    }

    // @custom:oz-upgrades-unsafe-allow constructor
    // solhint-disable-next-line no-empty-blocks
    constructor() initializer {}

    /// @notice used to initialize the contract
    function initialize(uint256 _hardcap, address _wethAddress, address _swapRouter, uint256 _startedAt, uint256 _finishedAt) external initializer {
        require(_hardcap > 0, "TokenTransformer: _hardcap cannot be 0");
        require(_startedAt > block.timestamp, "TokenTransformer: _startedAt limit exceeded");
        require(_finishedAt > _startedAt, "TokenTransformer: _finishedAt limit exceeded");

        __ReentrancyGuard_init();
        __Ownable_init();

        hardcap = _hardcap;
        wethAddress = _wethAddress;
        swapRouter = _swapRouter;

        startedAt = _startedAt;
        finishedAt = _finishedAt;
    }

    function reserveWithToken(address _tokenIn, uint256 _amountIn, uint256 _amountOutMinimum) external onlyStarted {
        require(supportedTokens[_tokenIn], "TokenTransformer: _tokenIn not support");
        require(_amountIn > 0, "TokenTransformer: _amountIn cannot be 0");

        uint256 _before = IERC20Upgradeable(_tokenIn).balanceOf(address(this));
        IERC20Upgradeable(_tokenIn).safeTransferFrom(msg.sender, address(this), _amountIn);
        _amountIn = IERC20Upgradeable(_tokenIn).balanceOf(address(this)) - _before;

        if (_tokenIn != wethAddress) {
            require(feeTiers[_tokenIn] > 0, "TokenTransformer: _tokenIn has not set the fee tier");

            _amountIn = _swap(_tokenIn, wethAddress, feeTiers[_tokenIn], _amountIn, _amountOutMinimum);
        }

        _reserve(msg.sender, _amountIn);
    }

    function reserve() external payable onlyStarted {
        IWETH(wethAddress).deposit{ value: msg.value }();

        _reserve(msg.sender, msg.value);
    }

    function _reserve(address _recipient, uint256 _amountIn) internal onlyAllowlist(_recipient) {
        require(_amountIn >= MIN_INVEST_AMOUNTS, "TokenTransformer: _amountIn below minimum");
        require(g.totalWeiContributed + _amountIn <= hardcap, "TokenTransformer: IDO has reached the hard cap amount");

        if (balanceOf[_recipient] == 0) {
            g.totalUsers++;
        }

        g.totalWeiContributed += _amountIn;
        balanceOf[_recipient] += _amountIn;
    }

    function claim() external nonReentrant onlyFinished onlyEligible(msg.sender) afterUniswapTransfer returns (uint256 myTokens) {
        myTokens = pendingTokens(msg.sender);

        claimed[msg.sender][0] = balanceOf[msg.sender];
        claimed[msg.sender][1] = myTokens;
        balanceOf[msg.sender] = 0;

        IERC20Upgradeable(archiToken).safeTransfer(msg.sender, myTokens);
    }

    function withdrawFund(address _recipient) external onlyOwner onlyFinished afterUniswapTransfer {
        uint256 _balance = IERC20Upgradeable(wethAddress).balanceOf(address(this));
        IERC20Upgradeable(wethAddress).safeTransfer(_recipient, _balance);
    }

    function _swap(address _tokenIn, address _tokenOut, uint24 _feeTier, uint256 _amountIn, uint256 _amountOutMinimum) internal returns (uint256 amountOut) {
        _approve(_tokenIn, swapRouter, _amountIn);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: _tokenIn,
            tokenOut: _tokenOut,
            fee: _feeTier,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: _amountIn,
            amountOutMinimum: _amountOutMinimum,
            sqrtPriceLimitX96: 0
        });

        amountOut = ISwapRouter(swapRouter).exactInputSingle(params);
    }

    function pendingTokens(address _recipient) public view returns (uint256) {
        if (g.totalWeiContributed == 0 || balanceOf[_recipient] == 0) {
            return 0;
        }

        uint256 percent = (balanceOf[_recipient] * PRECISION) / g.totalWeiContributed;
        uint256 myTokens = (TOTAL_SALE * percent) / PRECISION;

        return myTokens;
    }

    function getBlockData() public view returns (uint256 number, uint256 timestamp) {
        number = block.number;
        timestamp = block.timestamp;
    }

    function updateSupportedTokens(address[] memory _tokens, bool _state) external onlyOwner {
        for (uint256 i = 0; i < _tokens.length; i++) {
            supportedTokens[_tokens[i]] = _state;

            emit UpdateSupportedToken(_tokens[i], _state);
        }
    }

    function updateFeeTiers(address[] memory _tokens, uint24[] calldata _feeTiers) external onlyOwner {
        require(_tokens.length == _feeTiers.length, "TokenTransformer: Length mismatch");

        for (uint256 i = 0; i < _tokens.length; i++) {
            feeTiers[_tokens[i]] = _feeTiers[i];

            emit UpdateFeeTier(_tokens[i], _feeTiers[i]);
        }
    }

    function _approve(address _token, address _spender, uint256 _amount) internal {
        IERC20Upgradeable(_token).safeApprove(_spender, 0);
        IERC20Upgradeable(_token).safeApprove(_spender, _amount);
    }

    function calcTokenAndAmount(address _token0, address _token1) public view returns (address token0, address token1, uint256 amount0, uint256 amount1) {
        uint256 weiAmounts = (g.totalWeiContributed * WETH_MINT_PERCENT) / PRECISION;

        if (_token0 < _token1) {
            token0 = _token0;
            token1 = _token1;

            amount0 = TOKEN_MINT_AMOUNTS;
            amount1 = weiAmounts;
        } else {
            token0 = _token1;
            token1 = _token0;

            amount0 = weiAmounts;
            amount1 = TOKEN_MINT_AMOUNTS;
        }
    }

    function createPool(uint24 _poolFee, uint160 _sqrtPriceX96) external onlyOwner {
        (g.token0, g.token1, g.amount0, g.amount1) = calcTokenAndAmount(archiToken, wethAddress);

        g.poolFee = _poolFee;

        INonfungiblePositionManager(nonfungiblePositionManager).createAndInitializePoolIfNecessary(g.token0, g.token1, _poolFee, _sqrtPriceX96);
    }

    function createNewPosition() external onlyFinished beforeUniswapTransfer {
        (g.token0, g.token1, g.amount0Desired, g.amount1Desired) = calcTokenAndAmount(archiToken, wethAddress);

        IERC20Upgradeable(archiToken).safeTransferFrom(msg.sender, address(this), TOKEN_MINT_AMOUNTS);

        _approve(g.token0, address(nonfungiblePositionManager), g.amount0Desired);
        _approve(g.token1, address(nonfungiblePositionManager), g.amount1Desired);

        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: g.token0,
            token1: g.token1,
            fee: g.poolFee,
            tickLower: TICK_LOWER,
            tickUpper: TICK_UPPER,
            amount0Desired: g.amount0Desired,
            amount1Desired: g.amount1Desired,
            amount0Min: 0,
            amount1Min: 0,
            recipient: address(this),
            deadline: block.timestamp
        });

        (uint256 tokenId, uint256 liquidity, uint256 amount0, uint256 amount1) = INonfungiblePositionManager(nonfungiblePositionManager).mint(params);

        g.tokenId = tokenId;
        g.liquidity = liquidity;
        g.amount0 = amount0;
        g.amount1 = amount1;

        emit UniswapResult(tokenId, liquidity, amount0, amount1);
    }

    function setArchiToken(address _token) external onlyOwner {
        require(_token != address(0), "TokenTransformer: _token cannot be 0x0");
        require(archiToken == address(0), "TokenTransformer: Cannot run this function twice");

        archiToken = _token;
    }

    function setAllowlist(address _allowlist) external onlyOwner {
        require(_allowlist != address(0), "TokenTransformer: _allowlist cannot be 0x0");
        require(allowlist == address(0), "TokenTransformer: Cannot run this function twice");

        allowlist = _allowlist;
    }

    function setNonfungiblePositionManager(address _nonfungiblePositionManager) external onlyOwner {
        require(_nonfungiblePositionManager != address(0), "TokenTransformer: _nonfungiblePositionManager cannot be 0x0");
        require(nonfungiblePositionManager == address(0), "TokenTransformer: Cannot run this function twice");

        nonfungiblePositionManager = _nonfungiblePositionManager;
    }

    // function onERC721Received(address, address, uint, bytes calldata) external override returns (bytes4) {
    //     return IERC721ReceiverUpgradeable.onERC721Received.selector;
    // }
}

