pragma solidity 0.8.17;
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./OwnableUpgradeable.sol";
import "./PausableUpgradeable.sol";

import "./ReentrancyGuardUpgradeable.sol";
import "./EthReceiver.sol";
import "./MessageSenderApp.sol";
import "./IMessageReceiverApp.sol";
import "./IUnizenTradeV2.sol";
import "./IUnizenDexAggr.sol";
import "./Controller.sol";
// import "hardhat/console.sol";

contract UnizenTradeV2 is
    IUnizenTradeV2,
    OwnableUpgradeable,
    PausableUpgradeable,
    MessageSenderApp,
    IMessageReceiverApp,
    ReentrancyGuardUpgradeable,
    EthReceiver
{
    using SafeERC20 for IERC20;
    using Address for address payable;

    // address unizenDexAggregator;
    address public celrMessageBus;
    mapping(uint16 => address) public celrDestAddr;
    mapping(address => uint64) public celrPerUserNonce;
    mapping(uint16 => uint16) public celrChainStableDecimal; // used by both CELR and LZ
    address public celrStable;
    uint16 public celrStableDecimal;

    Controller private unizenController;

    function setCelrMessageBus(address messageBus) external onlyOwner {
        celrMessageBus = messageBus;
    }

    function setCelrDestAddr(
        uint16 chainId,
        address destAddr
    ) external onlyOwner {
        celrDestAddr[chainId] = destAddr;
    }

    function setCelrStable(address stable) external onlyOwner {
        celrStable = stable;
    }

    function setCelrStableDecimal(uint16 decimals) external onlyOwner {
        celrStableDecimal = decimals;
    }

    function setCelrChainStableDecimal(
        uint16 chainId,
        uint16 decimals
    ) external onlyOwner {
        celrChainStableDecimal[chainId] = decimals;
    }

    function setUnizenController(address controller) external onlyOwner {
        unizenController = Controller(payable(controller));
    }

    function initialize() public initializer {
        __UnizenDexAggr_init();
    }

    function __Controller_init_() internal onlyInitializing {
        __Ownable_init();
        __Pausable_init();
    }

    function __UnizenDexAggr_init() internal onlyInitializing {
        __Controller_init_();
        __ReentrancyGuard_init();
    }

    function swapCLR(
        IUnizenTradeV2.CrossChainSwapClr memory swapInfo,
        IUnizenTradeV2.SwapCall[] memory calls,
        IUnizenTradeV2.SwapCall[] memory dstCalls
    ) external payable nonReentrant {
        // TODO: SOME CHECKS HERE

        uint256 balanceStableBefore = IERC20(celrStable).balanceOf(
            address(this)
        );
        if (!swapInfo.isFromNative) {
            IERC20(swapInfo.srcToken).safeTransferFrom(
                msg.sender,
                address(this),
                swapInfo.amount
            );
        } else {
            require(
                msg.value >= swapInfo.amount + swapInfo.nativeFee,
                "Invalid-amount"
            );
        }
        // console.log("mytest %s", swapInfo.amount);

        for (uint8 i = 0; i < calls.length; i++) {
            require(calls[i].amount != 0, "Invalid-trade-amount");
            require(
                unizenController.isWhiteListedDex(calls[i].targetExchange),
                "Not-verified-dex"
            );
            swapInfo.amount = swapInfo.amount - calls[i].amount;
            if (!swapInfo.isFromNative) {
                IERC20(swapInfo.srcToken).safeApprove(
                    calls[i].targetExchange,
                    0
                );
                IERC20(swapInfo.srcToken).safeApprove(
                    calls[i].targetExchange,
                    calls[i].amount
                );
            }
            {
                bool success;
                if (swapInfo.isFromNative) {
                    success = _executeTrade(
                        calls[i].targetExchange,
                        calls[i].amount,
                        calls[i].data
                    );
                } else {
                    // console.log(calls[i].targetExchange, calls[i].amount);
                    success = _executeTrade(
                        calls[i].targetExchange,
                        0,
                        calls[i].data
                    );
                }
                require(success, "Call-Failed");
            }
        }

        if (swapInfo.srcToken != celrStable && swapInfo.amount > 0) {
            if (swapInfo.isFromNative) {
                swapInfo.nativeFee += swapInfo.amount;
            } else {
                // return diff amount
                IERC20(swapInfo.srcToken).safeTransfer(
                    msg.sender,
                    swapInfo.amount
                );
            }
        }
        // console.log(
        //     "mytest %s %s",
        //     IERC20(celrStable).balanceOf(address(this)),
        //     balanceStableBefore
        // );

        uint256 bridgeAmount = IERC20(celrStable).balanceOf(address(this)) -
            balanceStableBefore;
        // console.log(bridgeAmount);
        require(bridgeAmount > 0, "Something-went-wrong");
        bytes memory payload = abi.encode(
            // (bridgeAmount * 10 ** celrChainStableDecimal[swapInfo.dstChain]) /
            //     10 ** celrStableDecimal,
            msg.sender,
            dstCalls
        );
        uint64 retrieveNonce = celrPerUserNonce[msg.sender];
        celrPerUserNonce[msg.sender] = retrieveNonce + 1;
        _crossChainTransferWithSwap(
            celrDestAddr[swapInfo.dstChain],
            swapInfo.srcChain,
            swapInfo.dstChain,
            payload,
            200000,
            retrieveNonce,
            swapInfo.nativeFee,
            celrStable,
            bridgeAmount
        );

        emit IUnizenTradeV2.CrossChainSwapped(1, msg.sender, bridgeAmount);

        // bytes memory payload = abi.encode(
        //     (bridgeAmount * 10 ** chainStableDecimal[swapInfo.dstChain]) /
        //         10 ** stableDecimal,
        //     msg.sender,
        //     dstCalls
        // );
        // ILayerZeroEndpoint(layerZeroEndpoint).send{value: swapInfo.nativeFee}(
        //     swapInfo.dstChain,
        //     abi.encodePacked(destAddr[swapInfo.dstChain], address(this)),
        //     payload,
        //     payable(msg.sender),
        //     address(0),
        //     swapInfo.adapterParams
        // );
        // emit CrossChainSwapped(swapInfo.dstChain, msg.sender, bridgeAmount);
    }

    function _executeTrade(
        address _targetExchange,
        uint256 _nativeAmount,
        bytes memory _data
    ) internal returns (bool) {
        // solhint-disable-next-line avoid-low-level-calls
        (bool success, ) = _targetExchange.call{value: _nativeAmount}(_data);
        return success;
    }

    function _crossChainTransferWithSwap(
        address _receiver,
        uint64 _chainId,
        uint64 _dstChainId,
        bytes memory payload,
        uint32 _maxBridgeSlippage,
        uint64 _nonce,
        uint256 _fee,
        address srcTokenOut,
        uint256 srcAmtOut
    ) private {
        // bytes32 id = _computeSwapRequestId(msg.sender, _chainId, _dstChainId, payload);
        // bridge the intermediate token to destination chain along with the message
        // NOTE In production, it's better use a per-user per-transaction nonce so that it's less likely transferId collision
        // would happen at Bridge contract. Currently this nonce is a timestamp supplied by frontend
        sendMessageWithTransfer(
            _receiver,
            srcTokenOut,
            srcAmtOut,
            _dstChainId,
            _nonce,
            _maxBridgeSlippage,
            payload,
            MsgDataTypes.BridgeSendType.Liquidity,
            _fee,
            celrMessageBus
        );
    }

    /**
     * @notice called by MessageBus when the tokens are checked to be arrived at this contract's address.
               sends the amount received to the receiver. swaps beforehand if swap behavior is defined in message
     * NOTE: if the swap fails, it sends the tokens received directly to the receiver as fallback behavior
     * @param _token the address of the token sent through the bridge
     * @param _amount the amount of tokens received at this contract through the cross-chain bridge
     * @param _srcChainId source chain ID
     * @param _payload SwapRequest message that defines the swap behavior on this destination chain
     */
    function executeMessageWithTransfer(
        address, // _sender
        address _token,
        uint256 _amount,
        uint64 _srcChainId,
        bytes calldata _payload,
        address // executor
    )
        external
        payable
        override
        onlyMessageBus
        returns (IMessageReceiverApp.ExecutionStatus)
    {
        //TODO: implement trustedremotelookup check
        (address user, SwapCall[] memory dstCalls) = abi.decode(
            _payload,
            (address, SwapCall[])
        );

        if (dstCalls.length == 0) {
            // user doesnt want to swap, want to take stable
            IERC20(celrStable).safeTransfer(user, _amount);
            emit CrossChainSwapped(uint16(_srcChainId), user, _amount);
            return IMessageReceiverApp.ExecutionStatus.Success;
        }
        uint256 balanceStableBefore = IERC20(celrStable).balanceOf(
            address(this)
        );
        for (uint8 i = 0; i < dstCalls.length; i++) {
            require(
                dstCalls[i].amount >= 0 && dstCalls[i].amount <= _amount,
                "Invalid-trade-amount"
            );
            require(
                unizenController.isWhiteListedDex(dstCalls[i].targetExchange),
                "Not-verified-dex"
            );
            IERC20(celrStable).safeApprove(dstCalls[i].targetExchange, 0);
            IERC20(celrStable).safeApprove(dstCalls[i].targetExchange, _amount);
            _executeTrade(dstCalls[i].targetExchange, 0, dstCalls[i].data);
        }

        uint256 diff = IERC20(celrStable).balanceOf(address(this)) +
            _amount -
            balanceStableBefore;
        if (diff > 0) {
            IERC20(celrStable).safeTransfer(user, diff);
        }

        emit CrossChainSwapped(uint16(_srcChainId), user, _amount);

        // always return success since swap failure is already handled in-place
        return IMessageReceiverApp.ExecutionStatus.Success;
    }

    function emergencyWithdraw(address token, uint256 amount) public {
        IERC20(token).safeTransfer(msg.sender, amount);
    }

    modifier onlyMessageBus() {
        require(msg.sender == celrMessageBus, "caller is not message bus");
        _;
    }
}

