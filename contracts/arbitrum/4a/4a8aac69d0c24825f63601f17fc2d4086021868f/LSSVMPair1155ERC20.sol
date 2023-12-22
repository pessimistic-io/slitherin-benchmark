// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {SafeTransferLib} from "./SafeTransferLib.sol";
import {ERC20} from "./ERC20.sol";
import {IERC1155} from "./IERC1155.sol";
import {LSSVMPair1155} from "./LSSVMPair1155.sol";
import {ILSSVMPairFactoryLike} from "./ILSSVMPairFactoryLike.sol";
import {LSSVMRouter} from "./LSSVMRouter.sol";
import {ICurve} from "./ICurve.sol";
import {CurveErrorCodes} from "./CurveErrorCodes.sol";

/**
    @title An NFT/Token pair where the token is an ERC20
    @author boredGenius and 0xmons
 */
abstract contract LSSVMPair1155ERC20 is LSSVMPair1155 {
    using SafeTransferLib for ERC20;

    uint256 internal constant IMMUTABLE_PARAMS_LENGTH = 113;

    /**
        @notice Returns the ERC20 token associated with the pair
        @dev See LSSVMPairCloner for an explanation on how this works
     */
    function token() public pure returns (ERC20 _token) {
        uint256 paramsLength = _immutableParamsLength();
        assembly {
            _token := shr(
                0x60,
                calldataload(add(sub(calldatasize(), paramsLength), 61))
            )
        }
    }

    /// @inheritdoc LSSVMPair1155
    function _pullTokenInputAndPayProtocolFee(
        uint256 inputAmount,
        bool isRouter,
        address routerCaller,
        ILSSVMPairFactoryLike _factory,
        CurveErrorCodes.ProtocolFeeStruct memory protocolFeeStruct
    ) internal override {
        require(msg.value == 0, "ERC20 pair");

        ERC20 _token = token();
        address _assetRecipient = getAssetRecipient();

        if (isRouter) {
            // Verify if router is allowed
            LSSVMRouter router = LSSVMRouter(payable(msg.sender));

            // Locally scoped to avoid stack too deep
            {
                (bool routerAllowed, ) = _factory.routerStatus(router);
                require(routerAllowed, "Not router");
            }

            // Cache state and then call router to transfer tokens from user
            uint256 beforeBalance = _token.balanceOf(_assetRecipient);
            router.pairTransferERC20From(
                _token,
                routerCaller,
                _assetRecipient,
                inputAmount - protocolFeeStruct.totalProtocolFeeAmount,
                pairVariant()
            );

            // Verify token transfer (protect pair against malicious router)
            require(
                _token.balanceOf(_assetRecipient) - beforeBalance ==
                    inputAmount - protocolFeeStruct.totalProtocolFeeAmount,
                "ERC20 not transferred in"
            );

            for (uint i = 0; i < protocolFeeStruct.protocolFeeAmount.length;) {
                uint protocolFee = protocolFeeStruct.protocolFeeAmount[i];

                if (protocolFee > 0) {
                    router.pairTransferERC20From(
                        _token,
                        routerCaller,
                        protocolFeeStruct.protocolFeeReceiver[i],
                        protocolFee,
                        pairVariant()
                    );
                }
                unchecked {
                    ++i;
                }
            }

            // Note: no check for factory balance's because router is assumed to be set by factory owner
            // so there is no incentive to *not* pay protocol fee
        } else {
            // Transfer tokens directly
            _token.safeTransferFrom(
                msg.sender,
                _assetRecipient,
                inputAmount - protocolFeeStruct.totalProtocolFeeAmount
            );

            // Take protocol fee (if it exists)
            for (uint i = 0; i < protocolFeeStruct.protocolFeeAmount.length;) {
                uint protocolFee = protocolFeeStruct.protocolFeeAmount[i];

                if (protocolFee > 0) {
                    _token.safeTransferFrom(
                    msg.sender,
                    protocolFeeStruct.protocolFeeReceiver[i],
                    protocolFee
                );
                }
                unchecked {
                    ++i;
                }
            }
        }
    }

    /// @inheritdoc LSSVMPair1155
    function _refundTokenToSender(uint256 inputAmount) internal override {
        // Do nothing since we transferred the exact input amount
    }

    /// @inheritdoc LSSVMPair1155
    function _payProtocolFeeFromPair(
        CurveErrorCodes.ProtocolFeeStruct memory protocolFeeStruct
    ) internal override {
        ERC20 _token = token();

        // Take protocol fee (if it exists)
        for (uint i = 0; i < protocolFeeStruct.protocolFeeAmount.length;) {
            uint protocolFee = protocolFeeStruct.protocolFeeAmount[i];
            // Round down to the actual token balance if there are numerical stability issues with the bonding curve calculations
            uint256 pairTokenBalance = _token.balanceOf(address(this));
            if (protocolFee > pairTokenBalance) {
                protocolFee = pairTokenBalance;
            }
            if (protocolFee > 0) {
                _token.safeTransfer(
                    protocolFeeStruct.protocolFeeReceiver[i],
                    protocolFee
                );
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
        // Send tokens to caller
        if (outputAmount > 0) {
            token().safeTransfer(tokenRecipient, outputAmount);
        }
    }

    /// @inheritdoc LSSVMPair1155
    // @dev see LSSVMPairCloner for params length calculation
    function _immutableParamsLength() internal pure override returns (uint256) {
        return IMMUTABLE_PARAMS_LENGTH;
    }

    /// @inheritdoc LSSVMPair1155
    function withdrawERC20(ERC20 a, uint256 amount)
        external
        override
        onlyOwner
    {
        a.safeTransfer(msg.sender, amount);

        if (a == token()) {
            // emit event since it is the pair token
            emit TokenWithdrawal(amount);
        }
    }
}

