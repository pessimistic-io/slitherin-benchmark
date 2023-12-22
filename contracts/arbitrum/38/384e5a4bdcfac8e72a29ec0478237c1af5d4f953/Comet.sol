// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./Proxy.sol";
import "./IWETH9.sol";
import "./SafeERC20.sol";

interface IComet is IERC20 {
    function allow(address manager, bool isAllowed) external;
    function hasPermission(address owner, address manager) external view returns (bool);
    function collateralBalanceOf(address account, address asset) external view returns (uint128);
    function supplyTo(address dst, address asset, uint256 amount) external;
    function withdrawFrom(address src, address dst, address asset, uint256 amount) external;
}

/// @title Comet (Compound V3) proxy, similar to bulker contract
/// @author Matin Kaboli
/// @notice Supplies and Withdraws ERC20 and ETH tokens and helps with WETH wrapping
/// @dev This contract uses Permit2
contract Comet is Proxy {
    using SafeERC20 for IERC20;

    IComet public immutable CometInterface;

    /// @notice Receives cUSDCv3 and approves Compoound tokens to it
    /// @dev Do not put WETH address among _tokens list
    /// @param _comet cUSDCv3 address, used for supplying and withdrawing tokens
    /// @param _weth WETH address used in Comet protocol
    /// @param _tokens List of ERC20 tokens used in Compound V3
    constructor(Permit2 _permit2, IWETH9 _weth, IComet _comet, IERC20[] memory _tokens) Proxy(_permit2, _weth) {
        CometInterface = _comet;

        _weth.approve(address(_comet), type(uint256).max);

        for (uint8 i = 0; i < _tokens.length;) {
            _tokens[i].safeApprove(address(_comet), type(uint256).max);

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Supplies an ERC20 asset to Comet
    /// @param _permit Permit2 PermitTransferFrom struct, includes receiver, token and amount
    /// @param _signature Signature, used by Permit2
    function supply(ISignatureTransfer.PermitTransferFrom calldata _permit, bytes calldata _signature) public payable {
        permit2.permitTransferFrom(
            _permit,
            ISignatureTransfer.SignatureTransferDetails({to: address(this), requestedAmount: _permit.permitted.amount}),
            msg.sender,
            _signature
        );

        CometInterface.supplyTo(msg.sender, _permit.permitted.token, _permit.permitted.amount);
    }

    /// @notice Wraps ETH to WETH and supplies it to Comet
    /// @param _fee Fee of the proxy
    function supplyETH(uint256 _fee) public payable {
        require(msg.value > 0 && msg.value > _fee);

        uint256 ethAmount = msg.value - _fee;

        WETH.deposit{value: ethAmount}();
        CometInterface.supplyTo(msg.sender, address(WETH), ethAmount);
    }

    /// @notice Withdraws an ERC20 token and transfers it to msg.sender
    /// @param _asset ERC20 asset to withdraw
    /// @param _amount Amount of _asset to withdraw
    function withdraw(address _asset, uint256 _amount) public payable {
        CometInterface.withdrawFrom(msg.sender, msg.sender, _asset, _amount);
    }

    /// @notice Withdraws WETH and unwraps it to ETH and transfers it to msg.sender
    /// @param _amount Amount of WETh to withdraw
    function withdrawETH(uint256 _amount) public payable {
        CometInterface.withdrawFrom(msg.sender, address(this), address(WETH), _amount);
        WETH.withdraw(_amount);

        _sendETH(msg.sender, _amount);
    }
}

