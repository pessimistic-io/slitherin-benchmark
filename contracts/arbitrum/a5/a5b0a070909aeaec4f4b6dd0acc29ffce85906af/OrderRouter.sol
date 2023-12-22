// SPDX-License-Identifier: BUSL-1.1
// omnisea-contracts v0.1

pragma solidity ^0.8.7;

import "./IStargateRouter.sol";
import "./IStargateReceiver.sol";
import "./Ownable.sol";
import "./IERC20.sol";
import {OrderParams} from "./OrdersStructs.sol";
import "./TransferHelper.sol";
import "./ISwapRouter.sol";

contract OrderRouter is IStargateReceiver, Ownable {
    event ReceivedOnDestination(address indexed _token, uint256 _amount, bool success);
    event StargateReceived(address indexed _token, uint256 _amount);

    address public WETH9;
    address public USDC;
    uint24 public poolFee = 3000;

    IStargateRouter public stargateRouter;
    ISwapRouter public swapRouter;
    address public feeManager;
    uint256 public fee;
    uint16 public chainId;
    mapping(uint256 => address) public poolIdToToken;
    mapping(uint256 => address) public chainIdToRemoteStargate;

    /**
     * @notice Sets the contract owner, router, and indicates source chain name for mappings.
     *
     * @param _router A contract that handles cross-chain messaging used to extend ERC721 with omnichain capabilities.
     */
    constructor(uint16 _chainId, IStargateRouter _router, ISwapRouter _swapRouter, address _WETH, address _USDC) {
        chainId = _chainId;
        stargateRouter = _router;
        swapRouter = _swapRouter;
        feeManager = address(0x61104fBe07ecc735D8d84422c7f045f8d29DBf15);
        fee = 1;
        WETH9 = _WETH;
        USDC = _USDC;
    }

    function setStargateRouter(IStargateRouter _router) external onlyOwner {
        stargateRouter = _router;
    }

    function setSwapRouter(ISwapRouter _router) external onlyOwner {
        swapRouter = _router;
    }

    function setFeeManager(address _manager) external onlyOwner {
        feeManager = _manager;
    }

    function sendOrder(OrderParams calldata params) public payable {
        if (params.dstChainId == chainId) {
            require(params.tokenAmount > 0, "!tokenAmount");
            // fillOrder() direct on the source chain
            return;
        }
        address to = params.to != address(0) ? params.to : msg.sender;
        require(params.srcPoolId != 0 && params.dstPoolId != 0, "!srcPoolId || !dstPoolId");

        IERC20 token = IERC20(poolIdToToken[params.srcPoolId]);
        token.transferFrom(msg.sender, address(this), params.tokenAmount);
        token.approve(address(stargateRouter), params.tokenAmount);

        bytes memory data;
        {
            data = abi.encode(0, to);
            // TODO: (Must) calculate min native dst amount
        }

        stargateRouter.swap{value : msg.value}(
            params.dstChainId, // the destination chain id
            params.srcPoolId, // the source Stargate poolId
            params.dstPoolId, // the destination Stargate poolId
            payable(msg.sender), // refund adddress. if msg.sender pays too much gas, return extra eth
            params.tokenAmount, // total tokens to send to destination chain
            params.tokenAmount * 99 / 100, // minimum 99% - assuming stables for now
            LayerZeroTxConfig(params.gas, 0, "0x"),
            abi.encodePacked(chainIdToRemoteStargate[params.dstChainId]), // destination address, the sgReceive() implementer
            data // bytes payload
        );
    }

    function sgReceive(
        uint16 _srcChainId, // the remote chainId sending the tokens
        bytes memory _srcAddress, // the remote Bridge address
        uint256 _nonce,
        address _token, // the token contract on the local chain
        uint256 amountLD, // the qty of local _token contract tokens
        bytes memory payload
    ) external override {
        require(msg.sender == address(stargateRouter), "only stargate router can call sgReceive!");
        // TODO (Must) require (isTrustedRemote[_srcChainId] == _srcAddress)
        emit StargateReceived(_token, amountLD);

        (uint _amountOutMin, address _toAddr) = abi.decode(payload, (uint256, address));

        try this.fulfillOrder(IERC20(_token), amountLD, _toAddr) {
            emit ReceivedOnDestination(_token, amountLD, true);
        } catch {
            IERC20(_token).transfer(_toAddr, amountLD);
            emit ReceivedOnDestination(_token, amountLD, false);
        }
    }

    function setSG(uint256 _chainId, address _remote) external onlyOwner {
        chainIdToRemoteStargate[_chainId] = _remote;
    }

    function isSG(uint256 _chainId, address _remote) public view returns (bool) {
        return chainIdToRemoteStargate[_chainId] == _remote;
    }

    function fulfillOrder(IERC20 _token, uint256 _amountLD, address _to) external {
        // TODO: (Must) require(msg.sender == address(this), "!OrderRouter");
        _token.transfer(_to, _amountLD);
    }

//    function swapExactInputSingle(uint256 amountIn) external returns (uint256 amountOut) {
//        // msg.sender must approve this contract
//
//        // Transfer the specified amount of DAI to this contract.
//        TransferHelper.safeTransferFrom(USDC, msg.sender, address(this), amountIn);
//
//        // Approve the router to spend DAI.
//        TransferHelper.safeApprove(USDC, address(swapRouter), amountIn);
//
//        // Naively set amountOutMinimum to 0. In production, use an oracle or other data source to choose a safer value for amountOutMinimum.
//        // We also set the sqrtPriceLimitx96 to be 0 to ensure we swap our exact input amount.
//        ISwapRouter.ExactInputSingleParams memory params =
//            ISwapRouter.ExactInputSingleParams({
//            tokenIn : USDC,
//            tokenOut : WETH9,
//            fee : poolFee,
//            recipient : address(this), // Set to this contract because it'll perform fillOrder() using native
//            deadline : block.timestamp,
//            amountIn : amountIn,
//            amountOutMinimum : 0, // TODO (Must): Calculate in prod
//            sqrtPriceLimitX96 : 0
//        });
//
//        // The call to `exactInputSingle` executes the swap.
//        amountOut = swapRouter.exactInputSingle(params);
//    }

    receive() external payable {}
}

