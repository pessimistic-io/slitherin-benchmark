// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;
pragma abicoder v2;

import "./ILido.sol";
import "./Proxy.sol";
import "./IWETH9.sol";
import "./IWstETH.sol";
import "./SafeERC20.sol";

contract Lido is Proxy {
    using SafeERC20 for IERC20;

    ILido public immutable StETH;
    IWstETH public immutable WstETH;

    /// @notice Lido proxy contract
    /// @dev Lido and StETH contracts are the same
    /// @param _permit2 Permit2 contract address
    /// @param _weth WETH9 contract address
    /// @param _stETH StETH contract address
    /// @param _wstETH WstETH contract address
    constructor(Permit2 _permit2, IWETH9 _weth, ILido _stETH, IWstETH _wstETH) Proxy(_permit2, _weth) {
        StETH = _stETH;
        WstETH = _wstETH;

        _stETH.approve(address(_wstETH), type(uint256).max);
    }

    /// @notice Unwraps WETH to ETH
    function unwrapWETH() private {
        uint256 balanceWETH = WETH.balanceOf(address(this));

        if (balanceWETH > 0) {
            WETH.withdraw(balanceWETH);
        }
    }

    /// @notice Sweeps all ST_ETH tokens of the contract based on shares to msg.sender
    /// @dev This function uses sharesOf instead of balanceOf to transfer 100% of tokens
    function sweepStETH() private {
        StETH.transferShares(msg.sender, StETH.sharesOf(address(this)));
    }

    /// @notice Submits ETH to Lido protocol and transfers ST_ETH to msg.sender
    /// @param _proxyFee Fee of the proxy contract
    /// @return steth Amount of ST_ETH token that is being transferred to msg.sender
    function ethToStETH(uint256 _proxyFee) external payable returns (uint256 steth) {
        steth = StETH.submit{value: msg.value - _proxyFee}(msg.sender);

        sweepStETH();
    }

    /// @notice Converts ETH to WST_ETH and transfers WST_ETH to msg.sender
    /// @param _proxyFee Fee of the proxy contract
    function ethToWstETH(uint256 _proxyFee) external payable {
        _sendETH(address(WstETH), msg.value - _proxyFee);

        _sweepToken(address(WstETH));
    }

    /// @notice Submits WETH to Lido protocol and transfers ST_ETH to msg.sender
    /// @param _permit Permit2 PermitTransferFrom struct
    /// @param _signature Signature, used by Permit2
    /// @return steth Amount of ST_ETH token that is being transferred to msg.sender
    function wethToStETH(ISignatureTransfer.PermitTransferFrom calldata _permit, bytes calldata _signature)
        external
        payable
        returns (uint256 steth)
    {
        require(_permit.permitted.token == address(WETH));

        permit2.permitTransferFrom(
            _permit,
            ISignatureTransfer.SignatureTransferDetails({to: address(this), requestedAmount: _permit.permitted.amount}),
            msg.sender,
            _signature
        );

        unwrapWETH();

        steth = StETH.submit{value: _permit.permitted.amount}(msg.sender);

        sweepStETH();
    }

    /// @notice Submits WETH to Lido protocol and transfers WST_ETH to msg.sender
    /// @param _permit Permit2 PermitTransferFrom struct
    /// @param _signature Signature, used by Permit2
    function wethToWstETH(ISignatureTransfer.PermitTransferFrom calldata _permit, bytes calldata _signature)
        external
        payable
    {
        require(_permit.permitted.token == address(WETH));

        permit2.permitTransferFrom(
            _permit,
            ISignatureTransfer.SignatureTransferDetails({to: address(this), requestedAmount: _permit.permitted.amount}),
            msg.sender,
            _signature
        );

        unwrapWETH();

        _sendETH(address(WstETH), _permit.permitted.amount - msg.value);
        _sweepToken(address(WstETH));
    }

    /// @notice Wraps ST_ETH to WST_ETH and transfers it to msg.sender
    /// @param _permit Permit2 PermitTransferFrom struct
    /// @param _signature Signature, used by Permit2
    function stETHToWstETH(ISignatureTransfer.PermitTransferFrom calldata _permit, bytes calldata _signature)
        external
        payable
    {
        require(_permit.permitted.token == address(StETH));

        permit2.permitTransferFrom(
            _permit,
            ISignatureTransfer.SignatureTransferDetails({to: address(this), requestedAmount: _permit.permitted.amount}),
            msg.sender,
            _signature
        );

        WstETH.wrap(_permit.permitted.amount);
        _sweepToken(address(WstETH));
    }

    /// @notice Unwraps WST_ETH to ST_ETH and transfers it to msg.sender
    /// @param _permit Permit2 PermitTransferFrom struct
    /// @param _signature Signature, used by Permit2
    function wstETHToStETH(ISignatureTransfer.PermitTransferFrom calldata _permit, bytes calldata _signature)
        external
        payable
    {
        require(_permit.permitted.token == address(WstETH));

        permit2.permitTransferFrom(
            _permit,
            ISignatureTransfer.SignatureTransferDetails({to: address(this), requestedAmount: _permit.permitted.amount}),
            msg.sender,
            _signature
        );

        WstETH.unwrap(_permit.permitted.amount);
        sweepStETH();
    }
}

