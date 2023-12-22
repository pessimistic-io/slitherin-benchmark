// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./IWETHWithdrawAdapter.sol";
import "./IWETH.sol";
import "./IStargateRouter.sol";
import "./IACLManager.sol";

interface IStargateRouterETH {
    function stargateRouter() external view returns (IStargateRouter);

    function swapETH(
        uint16 _dstChainId, // destination Stargate chainId
        address payable _refundAddress, // refund additional messageFee to this address
        bytes calldata _toAddress, // the receiver of the destination ETH
        uint256 _amountLD, // the amount, in Local Decimals, to be swapped
        uint256 _minAmountLD // the minimum amount accepted out on destination
    ) external payable;
}

contract WETHWithdrawAdapter is IWETHWithdrawAdapter {
    IStargateRouterETH public immutable stargateRouterETH;
    IWETH public immutable WETH;
    IACLManager public immutable aclManager;
    address public refundAddress;
    uint16 public layer1ChainId;

    event SetRefundAddress(address indexed _refundAddress);
    event SetLayer1ChainId(uint16 indexed _chainId);

    modifier onlyGovernance() {
        require(aclManager.isGovernance(msg.sender), "ONLY_GOVERNANCE");
        _;
    }

    constructor(address _stargateRouterETH, address _weth, address _refundAddress, uint16 _layer1ChainId, address _aclManager) {
        stargateRouterETH = IStargateRouterETH(_stargateRouterETH);
        WETH = IWETH(_weth);
        layer1ChainId = _layer1ChainId;
        aclManager = IACLManager(_aclManager);

        _setRefundAddress(_refundAddress);
    }

    function setRefundAddress(address _refundAddress) external onlyGovernance {
        _setRefundAddress(_refundAddress);
    }

    function _setRefundAddress(address _refundAddress) internal {
        refundAddress = _refundAddress;
        emit SetRefundAddress(_refundAddress);
    }

    function setLayer1ChainId(uint16 _layer1ChainId) external onlyGovernance {
        _setLayer1ChainId(_layer1ChainId);
    }

    function _setLayer1ChainId(uint16 _layer1ChainId) internal {
        layer1ChainId = _layer1ChainId;
        emit SetLayer1ChainId(_layer1ChainId);
    }

    function withdraw(
        address recipient,
        uint256 amount,
        bytes memory
    ) external {
        WETH.transferFrom(msg.sender, address(this), amount);
        WETH.withdraw(amount);

        IStargateRouter.lzTxObj memory params = IStargateRouter.lzTxObj({
            dstGasForCall: 0,
            dstNativeAmount: 0,
            dstNativeAddr: abi.encodePacked(address(0))
        });

        IStargateRouter stargateRouter = stargateRouterETH.stargateRouter();
        (uint256 fee, ) = stargateRouter.quoteLayerZeroFee(
            layer1ChainId,
            1,
            abi.encodePacked(recipient),
            abi.encodePacked(''),
            params
        );

        stargateRouterETH.swapETH{value: amount}(
            layer1ChainId,
            payable(refundAddress),
            abi.encodePacked(recipient),
            amount - fee,
            amount - fee * 2
        );
    }

    receive() external payable {
    }
}

