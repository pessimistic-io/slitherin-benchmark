// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.10;

import {IParaSwapAugustus} from "./IParaSwapAugustus.sol";
import {ITwapQuery} from "./ITwapQuery.sol";
import { IERC20 } from "./IERC20.sol";
import {CustomOwnable} from "./CustomOwnable.sol";
import {CustomInitializable} from "./CustomInitializable.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";

contract TwapOrder is ITwapQuery, CustomOwnable, CustomInitializable, ReentrancyGuard {    
    address private constant AUGUSTUS_SWAPPER_ADDR = 0xDEF171Fe48CF0115B1d80b88dc8eAB59176FEe57;

    uint8 private constant STATE_ACTIVE = 1;
    uint8 private constant STATE_FINISHED = 2;
    uint8 private constant STATE_CANCELLED = 3;

    uint256 internal _startedOn;
    uint256 internal _deadline;
    uint256 internal _spent;
    uint256 internal _filled;
    uint256 internal _tradeSize;
    uint256 internal _priceLimit;
    uint256 internal _chunkSize;
    address public sellingTokenAddress;
    address public buyingTokenAddress;
    address public traderAddress;
    address public depositorAddress;

    uint8 internal _currentState;
    bool internal _orderAlive;

    event OnTraderChanged (address newAddr);
    event OnDepositorChanged (address newAddr);
    event OnCompletion ();
    event OnCancel ();
    event OnClose ();
    event OnOpen ();
    event OnSwap (address fromToken, uint256 fromAmount, address toToken, uint256 toAmount);


    constructor () {
        _owner = msg.sender;
    }

    modifier onlyTrader() {
        require(traderAddress == msg.sender, "Only trader");
        _;
    }

    modifier onlyDepositor() {
        require(depositorAddress == msg.sender, "Only depositor");
        _;
    }

    modifier ifCanCloseOrder () {
        require(_orderAlive, "Current order is not live");
        require(
            (_currentState == STATE_FINISHED || _currentState == STATE_CANCELLED) || 
            (_currentState == STATE_ACTIVE && block.timestamp > _deadline) // solhint-disable-line not-rely-on-time
        , "Cannot close order yet");
        _;
    }

    function initialize (address traderAddr, address depositorAddr, IERC20 sellingToken, IERC20 buyingToken) external onlyOwner ifNotInitialized {
        require(address(sellingToken) != address(buyingToken), "Invalid pair");

        traderAddress = traderAddr;
        depositorAddress = depositorAddr;
        sellingTokenAddress = address(sellingToken);
        buyingTokenAddress = address(buyingToken);

        _initializationCompleted();
    }

    function switchTrader (address traderAddr) external onlyOwner ifInitialized {
        require(traderAddr != address(0), "Invalid trader");
        require(traderAddr != traderAddress, "Trader already set");
        require(!_orderAlive, "Current order still alive");

        traderAddress = traderAddr;
        emit OnTraderChanged(traderAddr);
    }

    function switchDepositor (address depositorAddr) external onlyOwner ifInitialized {
        require(depositorAddr != address(0), "Invalid depositor");
        require(depositorAddr != depositorAddress, "Depositor already set");
        require(!_orderAlive, "Current order still alive");

        depositorAddress = depositorAddr;
        emit OnDepositorChanged(depositorAddr);
    }

    function updatePriceLimit (uint256 newPriceLimit) external onlyDepositor ifInitialized nonReentrant {
        require(newPriceLimit != _priceLimit, "Price limit already set");
        require(_currentState == STATE_ACTIVE, "Invalid state");
        require(_deadline > block.timestamp, "Deadline expired"); // solhint-disable-line not-rely-on-time

        _priceLimit = newPriceLimit;
    }

    function openOrder (uint256 durationInMins, uint256 targetQty, uint256 chunkSize, uint256 maxPriceLimit) external onlyDepositor ifInitialized {
        require(durationInMins >= 5, "Invalid duration");
        require(targetQty > 0, "Invalid trade size");
        require(chunkSize > 0, "Invalid chunk size");
        require(maxPriceLimit > 0, "Invalid price limit");
        require(!_orderAlive, "Current order still alive");

        _startedOn = block.timestamp; // solhint-disable-line not-rely-on-time
        _deadline = block.timestamp + (durationInMins * 1 minutes); // solhint-disable-line not-rely-on-time
        _tradeSize = targetQty;
        _chunkSize = chunkSize;
        _priceLimit = maxPriceLimit;
        _filled = 0;
        _spent = 0;
        _orderAlive = true;
        _currentState = STATE_ACTIVE;

        _approveProxy();
        emit OnOpen();
    }

    function deposit (uint256 depositAmount) external onlyDepositor ifInitialized {
        require(IERC20(sellingTokenAddress).transferFrom(msg.sender, address(this), depositAmount), "Deposit failed");
    }

    function swap (uint256 sellQty, uint256 buyQty, bytes memory payload) external nonReentrant onlyTrader ifInitialized {
        require(_currentState == STATE_ACTIVE, "Invalid state");
        require(_deadline > block.timestamp, "Deadline expired"); // solhint-disable-line not-rely-on-time
 
        IERC20 sellingToken = IERC20(sellingTokenAddress);
        uint256 sellingTokenBefore = sellingToken.balanceOf(address(this));
        require(sellingTokenBefore > 0, "Insufficient balance");

        IERC20 buyingToken = IERC20(buyingTokenAddress);
        uint256 buyingTokenBefore = buyingToken.balanceOf(address(this));

        // Swap
        (bool success,) = AUGUSTUS_SWAPPER_ADDR.call(payload); // solhint-disable-line avoid-low-level-calls
        require(success, "Swap failed");

        uint256 sellingTokenAfter = sellingToken.balanceOf(address(this));
        uint256 buyingTokenAfter = buyingToken.balanceOf(address(this));
        require(buyingTokenAfter > buyingTokenBefore, "Invalid swap: Buy");
        require(sellingTokenBefore > sellingTokenAfter, "Invalid swap: Sell");

        // The number of tokens received after running the swap
        uint256 tokensReceived = buyingTokenAfter - buyingTokenBefore;
        require(tokensReceived >= buyQty, "Invalid amount received");
        _filled += tokensReceived;

        // The number of tokens sold during this swap
        uint256 tokensSold = sellingTokenBefore - sellingTokenAfter;
        require(tokensSold <= sellQty, "Invalid amount spent");
        _spent += tokensSold;

        emit OnSwap(sellingTokenAddress, tokensSold, buyingTokenAddress, tokensReceived);

        if (buyingTokenAfter >= _tradeSize) {
            _currentState = STATE_FINISHED;
            emit OnCompletion();
        }
    }

    function cancelOrder () external nonReentrant onlyDepositor ifInitialized {
        require(_currentState == STATE_ACTIVE, "Invalid state");

        _currentState = STATE_CANCELLED;
        emit OnCancel();

        _closeOrder();
    }

    function closeOrder () external nonReentrant onlyDepositor ifInitialized {
        _closeOrder();
    }

    function _closeOrder () private ifCanCloseOrder {
        _orderAlive = false;

        IERC20 sellingToken = IERC20(sellingTokenAddress);
        IERC20 buyingToken = IERC20(buyingTokenAddress);
        uint256 sellingTokenBalance = sellingToken.balanceOf(address(this));
        uint256 buyingTokenBalance = buyingToken.balanceOf(address(this));

        if (sellingTokenBalance > 0) require(sellingToken.transfer(depositorAddress, sellingTokenBalance), "Transfer failed: sell");
        if (buyingTokenBalance > 0) require(buyingToken.transfer(depositorAddress, buyingTokenBalance), "Transfer failed: buy");
        _revokeProxy();

        emit OnClose();
    }

    function _approveProxy () private {
        IERC20 token = IERC20(sellingTokenAddress);
        address proxyAddr = IParaSwapAugustus(AUGUSTUS_SWAPPER_ADDR).getTokenTransferProxy();
        if (token.allowance(address(this), proxyAddr) != type(uint256).max) {
            require(token.approve(proxyAddr, type(uint256).max), "Token approval failed");
        }

        /*
        IERC20 token = IERC20(sellingTokenAddress);
        uint256 currentBalance = token.balanceOf(address(this));
        address proxyAddr = IParaSwapAugustus(AUGUSTUS_SWAPPER_ADDR).getTokenTransferProxy();
        if (token.allowance(address(this), proxyAddr) < currentBalance) {
            require(token.approve(proxyAddr, currentBalance), "Token approval failed");
        }
        */
    }

    function _revokeProxy () private {
        IERC20 token = IERC20(sellingTokenAddress);
        address proxyAddr = IParaSwapAugustus(AUGUSTUS_SWAPPER_ADDR).getTokenTransferProxy();
        if (token.allowance(address(this), proxyAddr) > 0) {
            require(token.approve(proxyAddr, 0), "Token approval failed");
        }
    }

    function getOrderMetrics () external view override returns (uint256 pStartedOn, uint256 pDeadline, uint256 pSpent, uint256 pFilled, uint256 pTradeSize, uint256 pChunkSize, uint256 pPriceLimit, address srcToken, address dstToken, uint8 pState, bool pAlive) {
        pDeadline = _deadline;
        pSpent = _spent;
        pFilled = _filled;
        pStartedOn = _startedOn;
        pTradeSize = _tradeSize;
        pChunkSize = _chunkSize;
        srcToken = sellingTokenAddress;
        dstToken = buyingTokenAddress;
        pState = _currentState;
        pAlive = _orderAlive;
        pPriceLimit = _priceLimit;
    }
}
