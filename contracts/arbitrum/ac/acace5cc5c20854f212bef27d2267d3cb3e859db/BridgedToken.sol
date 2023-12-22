// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {OFT} from "./OFT.sol";
import {OFTCore} from "./OFTCore.sol";
import {ITokenFactory} from "./ITokenFactory.sol";
import {ERC20, SafeTransferLib} from "./SafeTransferLib.sol";

contract BridgedToken is OFT {

    using SafeTransferLib for ERC20;

    address public deployer;
    address public nativeToken;
    bool public isOnNativeChain;

    error NotOnNativeChain();

    constructor(address _lzEndpoint) OFT(_lzEndpoint) {}

    function init(
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        address _nativeToken,
        uint16 _nativeChainId
    ) external {
        require(deployer == address(0), "BridgedToken: already initialized");
        deployer = msg.sender;
        _transferOwnership(msg.sender);
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
        nativeToken = _nativeToken;
        isOnNativeChain = lzEndpoint.getChainId() == _nativeChainId;
    }

    function wrap(uint256 _amount) external {
        if (!isOnNativeChain) revert NotOnNativeChain();
        ERC20(nativeToken).safeTransferFrom(msg.sender, address(this), _amount);
        _mint(msg.sender, _amount);
    }

    function unwrap(uint256 _amount) external {
        if (!isOnNativeChain) revert NotOnNativeChain();
        _burn(msg.sender, _amount);
        ERC20(nativeToken).safeTransfer(msg.sender, _amount);
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    function sendFrom(
        address _from,
        uint16 _dstChainId,
        bytes calldata _toAddress,
        uint256 _amount,
        address payable _refundAddress,
        address _zroPaymentAddress,
        bytes calldata _adapterParams
    ) public payable virtual override(OFTCore) {
        super.sendFrom(_from, _dstChainId, _toAddress, _amount, _refundAddress, _zroPaymentAddress, _adapterParams);
    }

    function _creditTo(uint16 _srcChain, address _toAddress, uint256 _amount) internal override returns (uint256 creditedAmount) {
        uint256 feeAmount = _amount * ITokenFactory(deployer).bridgeFee() / 100_000;
        creditedAmount = _amount - feeAmount;
        super._creditTo(_srcChain, ITokenFactory(deployer).feeTo(), feeAmount);
        super._creditTo(_srcChain, _toAddress, creditedAmount);
    }
}

