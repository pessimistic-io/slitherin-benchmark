// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./Proxy.sol";
import "./IWETH9.sol";
import "./SafeERC20.sol";

interface ICToken is IERC20 {
    function mint() external payable;
    function mint(uint256 mintAmount) external returns (uint256);
    function redeem(uint256 redeemTokens) external returns (uint256);
    function balanceOfUnderlying(address account) external returns (uint256);
}

/// @title Compound V2 proxy
/// @author Matin Kaboli
/// @notice Supplies and Withdraws ERC20 and ETH tokens and helps with WETH wrapping
/// @dev This contract uses Permit2
contract Compound is Proxy {
    using SafeERC20 for IERC20;

    /// @notice Receives tokens and cTokens and approves them
    /// @param _permit2 Address of Permit2 contract
    /// @param _tokens List of ERC20 tokens used in Compound V2
    /// @param _cTokens List of ERC20 cTokens used in Compound V2
    constructor(Permit2 _permit2, IWETH9 _weth, IERC20[] memory _tokens, address[] memory _cTokens)
        Proxy(_permit2, _weth)
    {
        for (uint8 i = 0; i < _tokens.length;) {
            _tokens[i].safeApprove(_cTokens[i], type(uint256).max);

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Supplies an ERC20 asset to Compound
    /// @param _permit Permit2 PermitTransferFrom struct, includes receiver, token and amount
    /// @param _signature Signature, used by Permit2
    function supply(ISignatureTransfer.PermitTransferFrom calldata _permit, bytes calldata _signature, ICToken _cToken)
        public
        payable
    {
        permit2.permitTransferFrom(
            _permit,
            ISignatureTransfer.SignatureTransferDetails({to: address(this), requestedAmount: _permit.permitted.amount}),
            msg.sender,
            _signature
        );

        uint256 balanceBefore = _cToken.balanceOf(address(this));

        _cToken.mint(_permit.permitted.amount);

        uint256 balanceAfter = _cToken.balanceOf(address(this));

        _cToken.transfer(msg.sender, balanceAfter - balanceBefore);
    }

    /// @notice Supplies ETH to Compound
    /// @param _cToken address of cETH
    /// @param _fee Fee of the protocol (could be 0)
    function supplyETH(ICToken _cToken, uint256 _fee) public payable {
        require(msg.value > 0 && msg.value > _fee);

        uint256 ethPrice = msg.value - _fee;

        uint256 balanceBefore = _cToken.balanceOf(address(this));

        _cToken.mint{value: ethPrice}();

        uint256 balanceAfter = _cToken.balanceOf(address(this));

        _cToken.transfer(msg.sender, balanceAfter - balanceBefore);
    }

    /// @notice Withdraws an ERC20 token and transfers it to msg.sender
    /// @param _permit Permit2 PermitTransferFrom struct, includes receiver, token and amount
    /// @param _signature Signature, used by Permit2
    /// @param _token received ERC20 token
    function withdraw(ISignatureTransfer.PermitTransferFrom calldata _permit, bytes calldata _signature, ICToken _token)
        public
        payable
    {
        permit2.permitTransferFrom(
            _permit,
            ISignatureTransfer.SignatureTransferDetails({to: address(this), requestedAmount: _permit.permitted.amount}),
            msg.sender,
            _signature
        );

        uint256 balanceBefore = _token.balanceOf(address(this));

        ICToken(_permit.permitted.token).redeem(_permit.permitted.amount);

        uint256 balanceAfter = _token.balanceOf(address(this));

        _token.transfer(msg.sender, balanceAfter - balanceBefore);
    }

    /// @notice Received cETH and unwraps it to ETH and transfers it to msg.sender
    /// @param _permit Permit2 PermitTransferFrom struct, includes receiver, token and amount
    /// @param _signature Signature, used by Permit2
    function withdrawETH(ISignatureTransfer.PermitTransferFrom calldata _permit, bytes calldata _signature)
        public
        payable
    {
        permit2.permitTransferFrom(
            _permit,
            ISignatureTransfer.SignatureTransferDetails({to: address(this), requestedAmount: _permit.permitted.amount}),
            msg.sender,
            _signature
        );

        uint256 balanceBefore = address(this).balance;

        ICToken(_permit.permitted.token).redeem(_permit.permitted.amount);

        uint256 balanceAfter = address(this).balance;

        _sendETH(msg.sender, balanceAfter - balanceBefore);
    }
}

