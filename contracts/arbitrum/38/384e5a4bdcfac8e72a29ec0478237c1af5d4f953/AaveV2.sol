// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./Proxy.sol";
import "./IWethGateway.sol";
import "./IWETH9.sol";
import "./SafeERC20.sol";

interface ILendingPool {
    function withdraw(address asset, uint256 amount, address to) external;
    function deposit(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;
    function borrow(address asset, uint256 amount, uint256 interestRateMode, uint16 referralCode, address onBehalfOf)
        external;
    function repay(address asset, uint256 amount, uint256 rateMode, address onBehalfOf) external;
}

/// @title AaveV2 proxy contract
/// @author Matin Kaboli
/// @notice Deposits and Withdraws ERC20 tokens to the lending pool
/// @dev This contract uses Permit2
contract AaveV2 is Proxy {
    using SafeERC20 for IERC20;

    ILendingPool public lendingPool;
    IWethGateway public wethGateway;

    /// @notice Sets LendingPool address and approves assets and aTokens to it
    /// @param _lendingPool Aave lending pool address
    /// @param _wethGateway Aave WethGateway contract address
    /// @param _permit2 Address of Permit2 contract
    /// @param _tokens ERC20 tokens, they're approved beforehand
    constructor(
        Permit2 _permit2,
        IWETH9 _weth,
        ILendingPool _lendingPool,
        IWethGateway _wethGateway,
        IERC20[] memory _tokens
    ) Proxy(_permit2, _weth) {
        lendingPool = _lendingPool;
        wethGateway = _wethGateway;

        for (uint8 i = 0; i < _tokens.length;) {
            _tokens[i].safeApprove(address(_lendingPool), type(uint256).max);

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Changes LendingPool and WethGateway address if necessary
    /// @param _lendingPool Address of the new lending pool contract
    /// @param _wethGateway Address of the new weth gateway
    function setNewAddresses(ILendingPool _lendingPool, IWethGateway _wethGateway) external onlyOwner {
        lendingPool = _lendingPool;
        wethGateway = _wethGateway;
    }

    /// @notice Deposits an ERC20 token to the pool and sends the underlying aToken to msg.sender
    /// @param _permit Permit2 PermitTransferFrom struct, includes receiver, token and amount
    /// @param _signature Signature, used by Permit2
    function supply(ISignatureTransfer.PermitTransferFrom calldata _permit, bytes calldata _signature)
        external
        payable
    {
        permit2.permitTransferFrom(
            _permit,
            ISignatureTransfer.SignatureTransferDetails({to: address(this), requestedAmount: _permit.permitted.amount}),
            msg.sender,
            _signature
        );

        lendingPool.deposit(_permit.permitted.token, _permit.permitted.amount, msg.sender, 0);
    }

    /// @notice Transfers ETH to WethGateway, then WethGateway converts ETH to WETH and deposits
    /// it to the pool and sends the underlying aToken to msg.sender
    /// @param _proxyFee Fee of the proxy
    function supplyETH(uint256 _proxyFee) external payable {
        require(msg.value > _proxyFee);

        wethGateway.depositETH{value: msg.value - _proxyFee}(address(lendingPool), msg.sender, 0);
    }

    /// @notice Receives underlying aToken and sends ERC20 token to msg.sender
    /// @param _permit Permit2 PermitTransferFrom struct, includes aToken and amount
    /// @param _signature Signature, used by Permit2
    /// @param _token ERC20 token to receive
    function withdraw(ISignatureTransfer.PermitTransferFrom calldata _permit, bytes calldata _signature, address _token)
        external
        payable
    {
        permit2.permitTransferFrom(
            _permit,
            ISignatureTransfer.SignatureTransferDetails({to: address(this), requestedAmount: _permit.permitted.amount}),
            msg.sender,
            _signature
        );

        lendingPool.withdraw(_token, _permit.permitted.amount, msg.sender);
    }

    /// @notice Receives underlying A_WETH and sends ETH token to msg.sender
    /// @param _permit Permit2 PermitTransferFrom struct, includes aToken and amount
    /// @param _signature Signature, used by Permit2
    function withdrawETH(ISignatureTransfer.PermitTransferFrom calldata _permit, bytes calldata _signature)
        external
        payable
    {
        permit2.permitTransferFrom(
            _permit,
            ISignatureTransfer.SignatureTransferDetails({to: address(this), requestedAmount: _permit.permitted.amount}),
            msg.sender,
            _signature
        );

        wethGateway.withdrawETH(address(lendingPool), _permit.permitted.amount, msg.sender);
    }

    /// @notice Repays a borrowed token
    /// @param _rateMode Rate mode, 1 for stable and 2 for variable
    /// @param _permit Permit2 PermitTransferFrom struct, includes aToken and amount
    /// @param _signature Signature, used by Permit2
    function repay(uint8 _rateMode, ISignatureTransfer.PermitTransferFrom calldata _permit, bytes calldata _signature)
        external
        payable
    {
        permit2.permitTransferFrom(
            _permit,
            ISignatureTransfer.SignatureTransferDetails({to: address(this), requestedAmount: _permit.permitted.amount}),
            msg.sender,
            _signature
        );

        lendingPool.repay(_permit.permitted.token, _permit.permitted.amount, _rateMode, msg.sender);

        _sweepToken(_permit.permitted.token);
    }

    ///// @notice Repays ETH
    ///// @param _rateMode Rate mode, 1 for stable and 2 for variable
    ///// @param _proxyFee Fee of the proxy contract
    // function repayETH(uint256 _rateMode, uint256 _proxyFee) external payable {
    //     wethGateway.repayETH{value: msg.value - _proxyFee}(address(lendingPool), msg.value - _proxyFee, _rateMode, msg.sender);
    // }

    /// @notice Repays ETH using WETH wrap/unwrap
    /// @param _rateMode Rate mode, 1 for stable and 2 for variable
    /// @param _proxyFee Fee of the proxy contract
    function repayETH(uint256 _rateMode, uint256 _proxyFee) external payable {
        WETH.deposit{value: msg.value - _proxyFee}();

        lendingPool.repay(address(WETH), msg.value - _proxyFee, _rateMode, msg.sender);

        _unwrapWETH9(msg.sender);
    }
}

