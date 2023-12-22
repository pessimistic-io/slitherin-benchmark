// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.17;

import "./EIP712.sol";
import "./SignatureChecker.sol";
import "./ITradeManager.sol";
import "./ITradeSignature.sol";

/**
 * @title TradeSignature
 * @notice This contract is used to verify signatures for trade orders
 * @dev This contract is based on the EIP712 standard
 */
contract TradeSignature is EIP712, ITradeSignature {
    bytes32 public constant OPEN_POSITION_ORDER_TYPEHASH = keccak256(
        "OpenPositionOrder(OpenPositionParams params,Constraints constraints,uint256 salt)Constraints(uint256 deadline,int256 minPrice,int256 maxPrice)OpenPositionParams(address tradePair,uint256 margin,uint256 leverage,bool isShort,address referrer,address whitelabelAddress)"
    );

    bytes32 public constant OPEN_POSITION_PARAMS_TYPEHASH = keccak256(
        "OpenPositionParams(address tradePair,uint256 margin,uint256 leverage,bool isShort,address referrer,address whitelabelAddress)"
    );

    bytes32 public constant CLOSE_POSITION_ORDER_TYPEHASH = keccak256(
        "ClosePositionOrder(ClosePositionParams params,Constraints constraints,bytes32 signatureHash,uint256 salt)ClosePositionParams(address tradePair,uint256 positionId)Constraints(uint256 deadline,int256 minPrice,int256 maxPrice)"
    );

    bytes32 public constant CLOSE_POSITION_PARAMS_TYPEHASH =
        keccak256("ClosePositionParams(address tradePair,uint256 positionId)");

    bytes32 public constant PARTIALLY_CLOSE_POSITION_ORDER_TYPEHASH = keccak256(
        "PartiallyClosePositionOrder(PartiallyClosePositionParams params,Constraints constraints,bytes32 signatureHash,uint256 salt)Constraints(uint256 deadline,int256 minPrice,int256 maxPrice)PartiallyClosePositionParams(address tradePair,uint256 positionId,uint256 proportion)"
    );

    bytes32 public constant PARTIALLY_CLOSE_POSITION_PARAMS_TYPEHASH =
        keccak256("PartiallyClosePositionParams(address tradePair,uint256 positionId,uint256 proportion)");

    bytes32 public constant EXTEND_POSITION_ORDER_TYPEHASH = keccak256(
        "ExtendPositionOrder(ExtendPositionParams params,Constraints constraints,bytes32 signatureHash,uint256 salt)Constraints(uint256 deadline,int256 minPrice,int256 maxPrice)ExtendPositionParams(address tradePair,uint256 positionId,uint256 addedMargin,uint256 addedLeverage)"
    );

    bytes32 public constant EXTEND_POSITION_PARAMS_TYPEHASH = keccak256(
        "ExtendPositionParams(address tradePair,uint256 positionId,uint256 addedMargin,uint256 addedLeverage)"
    );

    bytes32 public constant EXTEND_POSITION_TO_LEVERAGE_ORDER_TYPEHASH = keccak256(
        "ExtendPositionToLeverageOrder(ExtendPositionToLeverageParams params,Constraints constraints,bytes32 signatureHash,uint256 salt)Constraints(uint256 deadline,int256 minPrice,int256 maxPrice)ExtendPositionToLeverageParams(address tradePair,uint256 positionId,uint256 targetLeverage)"
    );

    bytes32 public constant EXTEND_POSITION_TO_LEVERAGE_PARAMS_TYPEHASH =
        keccak256("ExtendPositionToLeverageParams(address tradePair,uint256 positionId,uint256 targetLeverage)");

    bytes32 public constant REMOVE_MARGIN_FROM_POSITION_ORDER_TYPEHASH = keccak256(
        "RemoveMarginFromPositionOrder(RemoveMarginFromPositionParams params,Constraints constraints,bytes32 signatureHash,uint256 salt)Constraints(uint256 deadline,int256 minPrice,int256 maxPrice)RemoveMarginFromPositionParams(address tradePair,uint256 positionId,uint256 removedMargin)"
    );

    bytes32 public constant REMOVE_MARGIN_FROM_POSITION_PARAMS_TYPEHASH =
        keccak256("RemoveMarginFromPositionParams(address tradePair,uint256 positionId,uint256 removedMargin)");

    bytes32 public constant ADD_MARGIN_TO_POSITION_ORDER_TYPEHASH = keccak256(
        "AddMarginToPositionOrder(AddMarginToPositionParams params,Constraints constraints,bytes32 signatureHash,uint256 salt)AddMarginToPositionParams(address tradePair,uint256 positionId,uint256 addedMargin)Constraints(uint256 deadline,int256 minPrice,int256 maxPrice)"
    );

    bytes32 public constant ADD_MARGIN_TO_POSITION_PARAMS_TYPEHASH =
        keccak256("AddMarginToPositionParams(address tradePair,uint256 positionId,uint256 addedMargin)");

    bytes32 public constant CONSTRAINTS_TYPEHASH =
        keccak256("Constraints(uint256 deadline,int256 minPrice,int256 maxPrice)");

    mapping(bytes => bool) public isProcessedSignature;

    /**
     * @notice Constructs the TradeSignature Contract
     * @dev Constructs the EIP712 Contract
     */
    constructor() EIP712("UnlimitedLeverage", "1") {}

    /* =================== INTERNAL SIGNATURE FUNCTIONS ================== */

    function _processSignature(
        OpenPositionOrder calldata openPositionOrder_,
        address signer_,
        bytes calldata signature_
    ) internal {
        _onlyNonProcessedSignature(signature_);
        _verifySignature(hash(openPositionOrder_), signer_, signature_);
        _registerProcessedSignature(signature_);
    }

    function _processSignature(
        ClosePositionOrder calldata closePositionOrder_,
        address signer_,
        bytes calldata signature_
    ) internal {
        _onlyNonProcessedSignature(signature_);
        _verifySignature(hash(closePositionOrder_), signer_, signature_);
        _registerProcessedSignature(signature_);
    }

    function _processSignature(
        PartiallyClosePositionOrder calldata partiallyClosePositionOrder_,
        address signer_,
        bytes calldata signature_
    ) internal {
        _onlyNonProcessedSignature(signature_);
        _verifySignature(hashPartiallyClosePositionOrder(partiallyClosePositionOrder_), signer_, signature_);
        _registerProcessedSignature(signature_);
    }

    function _processSignatureExtendPosition(
        ExtendPositionOrder calldata extendPositionOrder_,
        address signer_,
        bytes calldata signature_
    ) internal {
        _onlyNonProcessedSignature(signature_);
        _verifySignature(hashExtendPositionOrder(extendPositionOrder_), signer_, signature_);
        _registerProcessedSignature(signature_);
    }

    function _processSignatureExtendPositionToLeverage(
        ExtendPositionToLeverageOrder calldata extendPositionToLeverageOrder_,
        address signer_,
        bytes calldata signature_
    ) internal {
        _onlyNonProcessedSignature(signature_);
        _verifySignature(hashExtendPositionToLeverageOrder(extendPositionToLeverageOrder_), signer_, signature_);
        _registerProcessedSignature(signature_);
    }

    function _processSignatureRemoveMarginFromPosition(
        RemoveMarginFromPositionOrder calldata removeMarginFromPositionOrder_,
        address signer_,
        bytes calldata signature_
    ) internal {
        _onlyNonProcessedSignature(signature_);
        _verifySignature(hashRemoveMarginFromPositionOrder(removeMarginFromPositionOrder_), signer_, signature_);
        _registerProcessedSignature(signature_);
    }

    function _processSignatureAddMarginToPosition(
        AddMarginToPositionOrder calldata addMarginToPositionOrder_,
        address signer_,
        bytes calldata signature_
    ) internal {
        _onlyNonProcessedSignature(signature_);
        _verifySignature(hashAddMarginToPositionOrder(addMarginToPositionOrder_), signer_, signature_);
        _registerProcessedSignature(signature_);
    }

    /* =================== INTERNAL FUNCTIONS ================== */

    function _verifySignature(bytes32 hash_, address signer_, bytes calldata signature_) private view {
        require(
            SignatureChecker.isValidSignatureNow(signer_, hash_, signature_),
            "TradeSignature::_verifySignature: Signature is not valid"
        );
    }

    function _registerProcessedSignature(bytes calldata signature_) private {
        isProcessedSignature[signature_] = true;
    }

    function _onlyNonProcessedSignature(bytes calldata signature_) private view {
        require(
            !isProcessedSignature[signature_], "TradeSignature::_onlyNonProcessedSignature: Signature already processed"
        );
    }

    /* =========== PUBLIC HASH FUNCTIONS =========== */

    function hash(OpenPositionOrder calldata openPositionOrder) public view returns (bytes32) {
        return _hashTypedDataV4(
            keccak256(
                abi.encode(
                    OPEN_POSITION_ORDER_TYPEHASH,
                    hash(openPositionOrder.params),
                    hash(openPositionOrder.constraints),
                    openPositionOrder.salt
                )
            )
        );
    }

    function hash(OpenPositionParams calldata openPositionParams) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                OPEN_POSITION_PARAMS_TYPEHASH,
                openPositionParams.tradePair,
                openPositionParams.margin,
                openPositionParams.leverage,
                openPositionParams.isShort,
                openPositionParams.referrer,
                openPositionParams.whitelabelAddress
            )
        );
    }

    function hash(ClosePositionOrder calldata closePositionOrder) public view returns (bytes32) {
        return _hashTypedDataV4(
            keccak256(
                abi.encode(
                    CLOSE_POSITION_ORDER_TYPEHASH,
                    hash(closePositionOrder.params),
                    hash(closePositionOrder.constraints),
                    closePositionOrder.signatureHash,
                    closePositionOrder.salt
                )
            )
        );
    }

    function hash(ClosePositionParams calldata closePositionParams) public pure returns (bytes32) {
        return keccak256(
            abi.encode(CLOSE_POSITION_PARAMS_TYPEHASH, closePositionParams.tradePair, closePositionParams.positionId)
        );
    }

    function hashPartiallyClosePositionOrder(PartiallyClosePositionOrder calldata partiallyClosePositionOrder)
        public
        view
        returns (bytes32)
    {
        return _hashTypedDataV4(
            keccak256(
                abi.encode(
                    PARTIALLY_CLOSE_POSITION_ORDER_TYPEHASH,
                    hashPartiallyClosePositionParams(partiallyClosePositionOrder.params),
                    hash(partiallyClosePositionOrder.constraints),
                    partiallyClosePositionOrder.signatureHash,
                    partiallyClosePositionOrder.salt
                )
            )
        );
    }

    function hashPartiallyClosePositionParams(PartiallyClosePositionParams calldata partiallyClosePositionParams)
        public
        pure
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                PARTIALLY_CLOSE_POSITION_PARAMS_TYPEHASH,
                partiallyClosePositionParams.tradePair,
                partiallyClosePositionParams.positionId,
                partiallyClosePositionParams.proportion
            )
        );
    }

    function hashExtendPositionOrder(ExtendPositionOrder calldata extendPositionOrder) public view returns (bytes32) {
        return _hashTypedDataV4(
            keccak256(
                abi.encode(
                    EXTEND_POSITION_ORDER_TYPEHASH,
                    hashExtendPositionParams(extendPositionOrder.params),
                    hash(extendPositionOrder.constraints),
                    extendPositionOrder.signatureHash,
                    extendPositionOrder.salt
                )
            )
        );
    }

    function hashExtendPositionParams(ExtendPositionParams calldata extendPositionParams)
        public
        pure
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                EXTEND_POSITION_PARAMS_TYPEHASH,
                extendPositionParams.tradePair,
                extendPositionParams.positionId,
                extendPositionParams.addedMargin,
                extendPositionParams.addedLeverage
            )
        );
    }

    function hashExtendPositionToLeverageOrder(ExtendPositionToLeverageOrder calldata extendPositionToLeverageOrder)
        public
        view
        returns (bytes32)
    {
        return _hashTypedDataV4(
            keccak256(
                abi.encode(
                    EXTEND_POSITION_TO_LEVERAGE_ORDER_TYPEHASH,
                    hashExtendPositionToLeverageParams(extendPositionToLeverageOrder.params),
                    hash(extendPositionToLeverageOrder.constraints),
                    extendPositionToLeverageOrder.signatureHash,
                    extendPositionToLeverageOrder.salt
                )
            )
        );
    }

    function hashExtendPositionToLeverageParams(ExtendPositionToLeverageParams calldata extendPositionToLeverageParams)
        public
        pure
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                EXTEND_POSITION_TO_LEVERAGE_PARAMS_TYPEHASH,
                extendPositionToLeverageParams.tradePair,
                extendPositionToLeverageParams.positionId,
                extendPositionToLeverageParams.targetLeverage
            )
        );
    }

    function hashAddMarginToPositionOrder(AddMarginToPositionOrder calldata addMarginToPositionOrder)
        public
        view
        returns (bytes32)
    {
        return _hashTypedDataV4(
            keccak256(
                abi.encode(
                    ADD_MARGIN_TO_POSITION_ORDER_TYPEHASH,
                    hashAddMarginToPositionParams(addMarginToPositionOrder.params),
                    hash(addMarginToPositionOrder.constraints),
                    addMarginToPositionOrder.signatureHash,
                    addMarginToPositionOrder.salt
                )
            )
        );
    }

    function hashAddMarginToPositionParams(AddMarginToPositionParams calldata addMarginToPositionParams)
        public
        pure
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                ADD_MARGIN_TO_POSITION_PARAMS_TYPEHASH,
                addMarginToPositionParams.tradePair,
                addMarginToPositionParams.positionId,
                addMarginToPositionParams.addedMargin
            )
        );
    }

    function hashRemoveMarginFromPositionOrder(RemoveMarginFromPositionOrder calldata removeMarginFromPositionOrder)
        public
        view
        returns (bytes32)
    {
        return _hashTypedDataV4(
            keccak256(
                abi.encode(
                    REMOVE_MARGIN_FROM_POSITION_ORDER_TYPEHASH,
                    hashRemoveMarginFromPositionParams(removeMarginFromPositionOrder.params),
                    hash(removeMarginFromPositionOrder.constraints),
                    removeMarginFromPositionOrder.signatureHash,
                    removeMarginFromPositionOrder.salt
                )
            )
        );
    }

    function hashRemoveMarginFromPositionParams(RemoveMarginFromPositionParams calldata removeMarginFromPositionParams)
        public
        pure
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                REMOVE_MARGIN_FROM_POSITION_PARAMS_TYPEHASH,
                removeMarginFromPositionParams.tradePair,
                removeMarginFromPositionParams.positionId,
                removeMarginFromPositionParams.removedMargin
            )
        );
    }

    function hash(Constraints calldata constraints) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(CONSTRAINTS_TYPEHASH, constraints.deadline, constraints.minPrice, constraints.maxPrice)
        );
    }
}

