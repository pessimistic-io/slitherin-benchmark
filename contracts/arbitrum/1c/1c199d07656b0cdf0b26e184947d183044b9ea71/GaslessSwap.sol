// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./SafeERC20.sol";
import "./ERC20.sol";
import {GelatoRelayContextERC2771} from "./GelatoRelayContextERC2771.sol";
import "./draft-IERC20Permit.sol";
import {SafeMath} from "./SafeMath.sol";
import {Multicall} from "./Multicall.sol";
import "./Ownable2Step.sol";

/// @title IUniswapV3Router Interface
/// @dev Minimal interface for our interactions with Uniswap V3's Router
interface IUniswapV3SwapRouter {
    struct ExactInputParams {
        bytes path;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
    }

    function exactInput(
        ExactInputParams calldata
    ) external payable returns (uint256);
}

interface IWETH {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
}

/** @title GaslessSwap Contract
    @notice Adapter for interacting with UniswapV3 swaps throguh gelato relay call
*/
contract GaslessSwap is GelatoRelayContextERC2771, Multicall, Ownable2Step {
    using SafeERC20 for ERC20;
    using SafeMath for uint256;

    address private immutable UNISWAP_V3_ROUTER;

    address private immutable WETH_TOKEN;

    address public FEE_RECEIVER;

    uint256 public PROTOCOL_FEE;

    uint256 public MAX_RELAY_FEE = 5e6;

    event SwapWithRelay(uint256 assetAmount, uint256 relayFee);

    event SetMaxRelayFee(uint256 fee);

    constructor(address _router, address _weth, address _feeReceiver) {
        UNISWAP_V3_ROUTER = _router;
        WETH_TOKEN = _weth;
        FEE_RECEIVER = _feeReceiver;
    }

    // @notice Set Relay fee in terms of usdc decimals
    function setMaxRelayFee(uint256 _maxFee) external onlyOwner {
        MAX_RELAY_FEE = _maxFee;
        emit SetMaxRelayFee(_maxFee);
    }

    function setProtocolConfig(address _feeReceiver, uint256 _fee) external onlyOwner{
        require(_feeReceiver != address(0), "setProtocolConfig: empty address");
        FEE_RECEIVER = _feeReceiver;
        PROTOCOL_FEE = _fee;
    }

    // EXTERNAL FUNCTIONS
    // @notice Trades assets on UniswapV3
    // @param _actionData Data specific to this action
    // @param _deadline permit deadline
    function swapTokensGasless(
        bytes calldata _actionData,
        uint256 _deadline,
        uint8 v,
        bytes32 r,
        bytes32 s,
        bytes calldata
    ) external 
    onlyGelatoRelayERC2771 
    {
        (
            address[] memory pathAddresses,
            uint24[] memory pathFees,
            uint256 outgoingAssetAmount,
            uint256 minIncomingAssetAmount
        ) = __decodeCallArgs(_actionData);

        _permitTransfer(
            _getMsgSender(),
            outgoingAssetAmount,
            _deadline,
            address(this),
            pathAddresses[0],
            v,
            r,
            s
        );

        uint256 relayFee = _getFee();
        outgoingAssetAmount = outgoingAssetAmount.sub(relayFee);
        uint256 prevBalance = ERC20(pathAddresses[1]).balanceOf(address(this));
        __uniswapV3Swap(
            address(this),
            pathAddresses,
            pathFees,
            outgoingAssetAmount,
            minIncomingAssetAmount
        );
        uint256 nextBalance = ERC20(pathAddresses[1]).balanceOf(address(this));
        uint256 tokensToTransfer = nextBalance.sub(prevBalance);
        if(pathAddresses[1] == WETH_TOKEN){
            IWETH(WETH_TOKEN).withdraw(tokensToTransfer);
            (bool success,) = payable(_getMsgSender()).call{value: tokensToTransfer}("");
            //  (bool success, ) = payable(msg.sender).call{value: address(this).balance}("");
            require(success, "Failed to send Ether");
        }
        emit SwapWithRelay(outgoingAssetAmount, relayFee);
        _transferRelayFeeCapped(MAX_RELAY_FEE);
    }


    // EXTERNAL FUNCTIONS
    // @notice Trades assets on UniswapV3
    // @param _actionData Data specific to this action
    // @param _deadline permit deadline
    function swapMultipleTokensGasless(
        bytes[] calldata actionData,
        uint256 deadline,
        address srcToken,
        uint256 amount,
        uint8 v,
        bytes32 r,
        bytes32 s,
        bytes calldata shouldUnWrap
    ) external 
    onlyGelatoRelayERC2771 
    {       
        _permitTransfer(
            _getMsgSender(),
            amount,
            deadline,
            address(this),
            srcToken,
            v,
            r,
            s
        );

        amount = _transferProtocolFee(srcToken, amount);

        uint256 totalOutgoingAmount;
        uint256 relayFee;

        for(uint256 i; i< actionData.length; ++i){        
        (
            address[] memory pathAddresses,
            uint24[] memory pathFees,
            uint256 outgoingAssetAmount,
            uint256 minIncomingAssetAmount
        ) = __decodeCallArgs(actionData[i]);

        require((totalOutgoingAmount.add(outgoingAssetAmount)) <= amount,"invalid action data");
        uint256 prevBalance = ERC20(pathAddresses[1]).balanceOf(address(this));

        __uniswapV3Swap(
            address(this),
            pathAddresses,
            pathFees,
            outgoingAssetAmount,
            minIncomingAssetAmount
        );

        uint256 nextBalance = ERC20(pathAddresses[1]).balanceOf(address(this));
        uint256 tokensToTransfer = nextBalance.sub(prevBalance);

        if(i == 0) {
            relayFee = _getFee();
            tokensToTransfer = tokensToTransfer.sub(relayFee);
        }

        if(pathAddresses[1] == WETH_TOKEN && abi.decode(shouldUnWrap, (bool))){
            IWETH(pathAddresses[1]).withdraw(tokensToTransfer);
            (bool success,) = payable(_getMsgSender()).call{value: tokensToTransfer}("");
            //  (bool success, ) = payable(msg.sender).call{value: address(this).balance}("");
            require(success, "Failed to send Ether");
        } else{
            ERC20(pathAddresses[1]).safeTransfer(_getMsgSender(), tokensToTransfer);
        }
        totalOutgoingAmount = totalOutgoingAmount.add(outgoingAssetAmount);
    }
        emit SwapWithRelay(amount, relayFee);
        _transferRelayFeeCapped(MAX_RELAY_FEE);
    }

    receive() payable external{}




    function _transferProtocolFee(address srcToken, uint256 amountIn) private returns(uint256){
        uint256 protocolFee = PROTOCOL_FEE;
        address feeReceiver = FEE_RECEIVER;
        require(amountIn > protocolFee, "_transferProtocolFee: insufficient amount");
        if(protocolFee != 0 && feeReceiver !=address(0))
            ERC20(srcToken).safeTransfer(feeReceiver, protocolFee);

        return amountIn.sub(protocolFee);
    }

    /**
     * @notice deposits USDC to this contract for swapping tokens
     * @dev transfers USDC to the contract using ERC20 permit
     * @param _depositer sender address
     * @param _amount the amount of USDC being deposited,
     * @param _deadline  permit
     * @param v, @param r, and @param s signature parameters
     */
    function _permitTransfer(
        address _depositer,
        uint256 _amount,
        uint256 _deadline,
        address _spender,
        address asset,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal {
        require(_amount != 0, "PermitTransfer:Invalid Amount");

        if (v != uint8(0)) {
            IERC20Permit(asset).permit(
                _depositer,
                address(this),
                _amount,
                _deadline,
                v,
                r,
                s
            );
        }
        ERC20(asset).safeTransferFrom(_depositer, _spender, _amount);
    }

    /// @dev Helper to execute a swap
    // UniswapV3 paths are packed encoded as (address(_pathAddresses[i]), uint24(_pathFees[i]), address(_pathAddresses[i + 1]), [...])
    // _pathFees[i] represents the fee for the pool between _pathAddresses(i) and _pathAddresses(i+1)
    function __uniswapV3Swap(
        address _recipient,
        address[] memory _pathAddresses,
        uint24[] memory _pathFees,
        uint256 _outgoingAssetAmount,
        uint256 _minIncomingAssetAmount
    ) internal {
        __approveAssetMaxAsNeeded(
            _pathAddresses[0],
            UNISWAP_V3_ROUTER,
            _outgoingAssetAmount
        );

        bytes memory encodedPath;

        for (uint256 i; i < _pathAddresses.length; i++) {
            if (i != _pathAddresses.length - 1) {
                encodedPath = abi.encodePacked(
                    encodedPath,
                    _pathAddresses[i],
                    _pathFees[i]
                );
            } else {
                encodedPath = abi.encodePacked(encodedPath, _pathAddresses[i]);
            }
        }

        IUniswapV3SwapRouter.ExactInputParams
            memory input = IUniswapV3SwapRouter.ExactInputParams({
                path: encodedPath,
                recipient: _recipient,
                deadline: block.timestamp + 1,
                amountIn: _outgoingAssetAmount,
                amountOutMinimum: _minIncomingAssetAmount
            });

        // Execute fill
        IUniswapV3SwapRouter(UNISWAP_V3_ROUTER).exactInput(input);
    }

    /// @dev Helper to decode the encoded callOnIntegration call arguments
    function __decodeCallArgs(
        bytes memory _actionData
    )
        private
        pure
        returns (
            address[] memory pathAddresses,
            uint24[] memory pathFees,
            uint256 outgoingAssetAmount,
            uint256 minIncomingAssetAmount
        )
    {
        return abi.decode(_actionData, (address[], uint24[], uint256, uint256));
    }

    /// @dev Helper to approve a target account with the max amount of an asset.
    /// This is helpful for fully trusted contracts, such as adapters that
    /// interact with external protocol like Uniswap, Compound, etc.
    function __approveAssetMaxAsNeeded(
        address _asset,
        address _target,
        uint256 _neededAmount
    ) internal {
        uint256 allowance = ERC20(_asset).allowance(address(this), _target);
        if (allowance < _neededAmount) {
            if (allowance > 0) {
                ERC20(_asset).safeApprove(_target, 0);
            }
            ERC20(_asset).safeApprove(_target, type(uint256).max);
        }
    }
}

