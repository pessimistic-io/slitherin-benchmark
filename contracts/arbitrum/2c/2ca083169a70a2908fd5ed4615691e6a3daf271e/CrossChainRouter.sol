//SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "./DForceDexRouter.sol";
import "./RouterEvent.sol";
import "./IWETH.sol";
import { IMessageBus, IBridge } from "./ICeler.sol";
import "./draft-EIP712Upgradeable.sol";

contract CrossChainRouter is DForceDexRouter, RouterEvent, EIP712Upgradeable {
    using Address for address;
    using SafeERC20 for IERC20;

    event SetMBusSupport(address _old, address _new);
    event SetSignAddress(address _old, address _new);
    event SetFeeRecipient(address _old, address _new);

    bytes32 private constant CROSS_FEE_HASH = keccak256("CrossFee(address token,uint256 amount,uint256 deadline)");

    address public immutable wGasToken;
    address public mBusSupport;

    address public signAddress;
    address public feeRecipient;

    function reinitialize() public reinitializer(2) {
        __EIP712_init("Cross swap router", "1");
    }

    constructor(address _wGasToken) DForceDexRouter() {
        reinitialize();
        wGasToken = _wGasToken;
    }

    modifier onlyMessageBus() {
        require(msg.sender == messageBus(), "CrossChainRouter: caller is not message bus");
        _;
    }

    function messageBus() public view returns (address) {
        return IMBusSupport(mBusSupport).messageBus();
    }

    function cbridge() public view returns (address) {
        return IMessageBus(messageBus()).liquidityBridge();
    }

    ///@param _first Whether to swap first
    function crossChainSwap(
        SwapBaseInfo memory _baseInfo,
        CrossParams memory _crossParams,
        uint64 _dstChainId,
        address _dstContract,
        address _crossToken,
        uint32 _maxSlippage,
        bool _first,
        SwapInfo memory _swapInfo
    ) external payable returns (bytes32 _transferId) {
        if (_baseInfo._from == ETH) {
            require(msg.value >= _baseInfo._amount, "CrossChainRouter: msg.value not enough");
        } else {
            IERC20(_baseInfo._from).safeTransferFrom(msg.sender, address(this), _baseInfo._amount);
        }

        if (_first) {
            _baseInfo._amount = this._blendSwap(_baseInfo, _swapInfo);
            _safeApprove(IERC20(_crossToken), cbridge(), _baseInfo._amount);
            // slippage * 1M, eg. 0.5% -> 5000
            IBridge(cbridge()).send(msg.sender, _crossToken, _baseInfo._amount, _dstChainId, _crossParams._cbridgeNonce, _crossParams._cbridgeMaxSlippage);
        } else {
            require(_crossParams._deadline > block.timestamp, "CrossChainRouter: Cross fee verification time expired");
            require(_verifyCrossFee(_crossParams._token, _crossParams._amount, _crossParams._deadline, _crossParams._signature), "CrossChainRouter: Cross fee verification failed");
            bytes memory _returns = mBusSupport.functionDelegateCall(
                abi.encodeWithSelector(IMBusSupport._crossChainSwap.selector, _baseInfo, _crossParams._amount, _dstChainId, _dstContract, _crossToken, _maxSlippage, !_first, _swapInfo)
            );
            _transferId = abi.decode(_returns, (bytes32));
        }
    }

    function getMBusFee(
        SwapBaseInfo memory _baseInfo,
        CrossParams memory _crossParams,
        bool _first,
        SwapInfo memory _swapInfo
    ) external view returns (uint256 _fee) {
        bytes memory _returns = mBusSupport.functionStaticCall(abi.encodeWithSelector(IMBusSupport.getFee.selector, _baseInfo, _crossParams._amount, !_first, _swapInfo));
        (, _fee) = abi.decode(_returns, (bytes, uint256));
    }

    function executeMessageWithTransfer(
        address, //Send cross chain contracts
        address _token,
        uint256 _amount,
        uint64, //_srcChainId, Source chain number
        bytes calldata _message, //send data
        address //_executor
    ) external payable onlyMessageBus returns (ExecutionStatus) {
        _warpGasToken(_token, _amount);
        CrossChainData memory _data = abi.decode(_message, (CrossChainData));
        _amount -= _data._crossFee;
        if (_data._swap) {
            _data._baseInfo._from = _token;
            _data._baseInfo._amount = _amount;
            uint256 _returns = this._blendSwap(_data._baseInfo, _data._swapInfo);
            ///@dev If _baseInfo._to is gasToken, it will be replaced with wtoken when it is passed in
            _transfer(_data._receiver, _data._baseInfo._to, _returns);
            emit CrossSwap(_data._receiver, _token, _data._baseInfo._to, _amount, _returns);
        } else {
            _transfer(_data._receiver, _token, _amount);
            emit OnlyReceive(_data._baseInfo._to, _token, _amount);
        }
        _transfer(feeRecipient, _token, _data._crossFee);
        return ExecutionStatus.Success;
    }

    //Bridge error call this
    function executeMessageWithTransferRefund(
        address _token,
        uint256 _amount,
        bytes calldata _message,
        address //_executor
    ) external payable onlyMessageBus returns (ExecutionStatus) {
        _warpGasToken(_token, _amount);
        CrossChainData memory _data = abi.decode(_message, (CrossChainData));
        _amount -= _data._crossFee;
        address _refund = _transfer(_data._receiver, _token, _amount);
        emit TransferRefund(_data._receiver, _refund, _amount);
        _transfer(feeRecipient, _token, _data._crossFee);
        return ExecutionStatus.Success;
    }

    //Target Chain Transaction error call this
    function executeMessageWithTransferFallback(
        address, //_sender
        address _token,
        uint256 _amount,
        uint64, //_srcChainId
        bytes memory _message,
        address //_executor
    ) external payable onlyMessageBus returns (ExecutionStatus) {
        _warpGasToken(_token, _amount);
        CrossChainData memory _data = abi.decode(_message, (CrossChainData));
        _amount -= _data._crossFee;
        address _refund = _transfer(_data._receiver, _token, _amount);
        emit TransferFallback(_data._receiver, _refund, _amount);
        _transfer(feeRecipient, _token, _data._crossFee);
        return ExecutionStatus.Success;
    }

    function setMBusSupport(address _new) external onlyOwner {
        address _old = mBusSupport;
        mBusSupport = _new;
        emit SetMBusSupport(_old, _new);
    }

    function setFeeRecipient(address _new) external onlyOwner {
        address _old = feeRecipient;
        feeRecipient = _new;
        emit SetFeeRecipient(_old, _new);
    }

    function setSignAddress(address _new) external onlyOwner {
        address _old = signAddress;
        signAddress = _new;
        emit SetSignAddress(_old, _new);
    }

    function _transfer(
        address _receiver,
        address _token,
        uint256 _amount
    ) private returns (address) {
        if (_token == ETH) {
            payable(_receiver).transfer(_amount);
            return ETH;
        } else {
            IERC20(_token).safeTransfer(_receiver, _amount);
            return _token;
        }
    }

    function ownerTransfer(
        address _token,
        address _to,
        uint256 _amount
    ) public onlyOwner {
        IERC20(_token).safeTransfer(_to, _amount);
    }

    function ownerTransferETH(address _to, uint256 _amount) public onlyOwner {
        payable(_to).transfer(_amount);
    }

    function _warpGasToken(address _token, uint256 _amount) internal {
        if (_token == wGasToken) IWETH(wGasToken).deposit{ value: _amount }();
    }

    function _verifyCrossFee(
        address _token,
        uint256 _amount,
        uint256 _deadline,
        bytes memory _signature
    ) internal view returns (bool) {
        bytes32 digest = _hashTypedDataV4(keccak256(abi.encode(CROSS_FEE_HASH, _token, _amount, _deadline)));
        return signAddress == ECDSAUpgradeable.recover(digest, _signature);
    }
}

