// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {ERC20} from "./ERC20.sol";
import {IERC1155} from "./IERC1155.sol";
import {SafeTransferLib} from "./SafeTransferLib.sol";
import {LSSVMPair1155} from "./LSSVMPair1155.sol";
import {ILSSVMPairFactoryLike} from "./ILSSVMPairFactoryLike.sol";
import {ICurve} from "./ICurve.sol";
import {CurveErrorCodes} from "./CurveErrorCodes.sol";

/**
    @title An NFT/Token pair where the token is ETH
    @author boredGenius and 0xmons
 */
abstract contract LSSVMPair1155ETH is LSSVMPair1155 {
    using SafeTransferLib for address payable;
    using SafeTransferLib for ERC20;

    uint256 internal constant IMMUTABLE_PARAMS_LENGTH = 93;

    /// @inheritdoc LSSVMPair1155
    function _pullTokenInputAndPayProtocolFee(
        uint256 inputAmount,
        bool, /*isRouter*/
        address, /*routerCaller*/
        ILSSVMPairFactoryLike _factory,
        CurveErrorCodes.ProtocolFeeStruct memory protocolFeeStruct
    ) internal override {
        require(msg.value >= inputAmount, "Sent too little ETH");

        // Transfer inputAmount ETH to assetRecipient if it's been set
        address payable _assetRecipient = getAssetRecipient();
        if (_assetRecipient != address(this)) {
            _assetRecipient.safeTransferETH(inputAmount - protocolFeeStruct.totalProtocolFeeAmount);
        }

        // Take protocol fee
        for (uint i = 0; i < protocolFeeStruct.protocolFeeAmount.length;) {
            uint protocolFee = protocolFeeStruct.protocolFeeAmount[i];
            if (protocolFee > address(this).balance) {
                protocolFee = address(this).balance;
            }

            if (protocolFee > 0) {
                payable(protocolFeeStruct.protocolFeeReceiver[i]).safeTransferETH(protocolFeeStruct.protocolFeeAmount[i]);
            }
            unchecked {
                ++i;
            }
        }
    }

    /// @inheritdoc LSSVMPair1155
    function _refundTokenToSender(uint256 inputAmount) internal override {
        // Give excess ETH back to caller
        if (msg.value > inputAmount) {
            payable(msg.sender).safeTransferETH(msg.value - inputAmount);
        }
    }

    /// @inheritdoc LSSVMPair1155
    function _payProtocolFeeFromPair(
        CurveErrorCodes.ProtocolFeeStruct memory protocolFeeStruct
    ) internal override {
        // Take protocol fee
        for (uint i = 0; i < protocolFeeStruct.protocolFeeAmount.length;) {
            uint protocolFee = protocolFeeStruct.protocolFeeAmount[i];
            // Round down to the actual ETH balance if there are numerical stability issues with the bonding curve calculations
            if (protocolFee > address(this).balance) {
                protocolFee = address(this).balance;
            }

            if (protocolFee > 0) {
                payable(protocolFeeStruct.protocolFeeReceiver[i]).safeTransferETH(protocolFeeStruct.protocolFeeAmount[i]);
            }
            unchecked {
                ++i;
            }
        }
    }

    /// @inheritdoc LSSVMPair1155
    function _sendTokenOutput(
        address payable tokenRecipient,
        uint256 outputAmount
    ) internal override {
        // Send ETH to caller
        if (outputAmount > 0) {
            tokenRecipient.safeTransferETH(outputAmount);
        }
    }

    /// @inheritdoc LSSVMPair1155
    // @dev see LSSVMPairCloner for params length calculation
    function _immutableParamsLength() internal pure override returns (uint256) {
        return IMMUTABLE_PARAMS_LENGTH;
    }

    /**
        @notice Withdraws all token owned by the pair to the owner address.
        @dev Only callable by the owner.
     */
    function withdrawAllETH() external onlyOwner {
        withdrawETH(address(this).balance);
    }

    /**
        @notice Withdraws a specified amount of token owned by the pair to the owner address.
        @dev Only callable by the owner.
        @param amount The amount of token to send to the owner. If the pair's balance is less than
        this value, the transaction will be reverted.
     */
    function withdrawETH(uint256 amount) public onlyOwner {
        payable(owner()).safeTransferETH(amount);

        // emit event since ETH is the pair token
        emit TokenWithdrawal(amount);
    }

    /// @inheritdoc LSSVMPair1155
    function withdrawERC20(ERC20 a, uint256 amount)
        external
        override
        onlyOwner
    {
        a.safeTransfer(msg.sender, amount);
    }

    /**
        @dev All ETH transfers into the pair are accepted. This is the main method
        for the owner to top up the pair's token reserves.
     */
    receive() external payable {
        emit TokenDeposit(msg.value);
    }

    /**
        @dev All ETH transfers into the pair are accepted. This is the main method
        for the owner to top up the pair's token reserves.
     */
    fallback() external payable {
        // Only allow calls without function selector
        require (msg.data.length == _immutableParamsLength()); 
        emit TokenDeposit(msg.value);
    }
}

