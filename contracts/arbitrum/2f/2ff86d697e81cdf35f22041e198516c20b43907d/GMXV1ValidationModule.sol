// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {decodeExecuteCallOpCalldata} from "./DecodeUtils.sol";
import {ECDSA} from "./ECDSA.sol";
import {UserOperation, ISessionValidationModule} from "./ISessionValidationModule.sol";

import {IRouter} from "./IRouter.sol";
import {IPositionRouter} from "./IPositionRouter.sol";
import {IReferralStorage} from "./IReferralStorage.sol";
import {UserOperationLib} from "./UserOperation.sol";

contract GMXV1ValidationModule is ISessionValidationModule {
    using UserOperationLib for UserOperation;

    address immutable router;
    address immutable orderbook;
    address immutable positionRouter;
    address immutable referralStorage;

    constructor(
        address router_,
        address orderbook_,
        address positionRouter_,
        address referralStorage_
    ) {
        router = router_;
        orderbook = orderbook_;
        positionRouter = positionRouter_;
        referralStorage = referralStorage_;
    }

    /**
     * @dev validates if the _op (UserOperation) matches the SessionKey permissions
     * and that _op has been signed by this SessionKey
     * Please mind the decimals of your exact token when setting maxAmount
     * @param _op User Operation to be validated.
     * @param _userOpHash Hash of the User Operation to be validated.
     * @param _sessionKeyData SessionKey data, that describes sessionKey permissions
     * @param _sessionKeySignature Signature over the the _userOpHash.
     * @return true if the _op is valid, false otherwise.
     */
    function validateSessionUserOp(
        UserOperation calldata _op,
        bytes32 _userOpHash,
        bytes calldata _sessionKeyData,
        bytes calldata _sessionKeySignature
    ) external pure override returns (bool) {
        revert("GMXV1ValidationModule: Not Implemented");
    }

    /**
     * @dev validates that the call (destinationContract, callValue, funcCallData)
     * complies with the Session Key permissions represented by sessionKeyData
     * @param destinationContract address of the contract to be called
     * @param callValue value to be sent with the call
     * @param _funcCallData the data for the call. is parsed inside the SVM
     * @param _sessionKeyData SessionKey data, that describes sessionKey permissions
     */
    function validateSessionParams(
        address destinationContract,
        uint256 callValue,
        bytes calldata _funcCallData,
        bytes calldata _sessionKeyData,
        bytes calldata _callSpecificData
    ) external virtual override returns (address) {
        address sender = address(bytes20(_sessionKeyData[20:40]));

        // bytes (bytes4 selector + padded address of 32 bytes + uint256 of 32 bytes + offset of bytes32 + length of bytes32 + bytes4 of selector) i.e. 4+32+32+32+32 = 132 to 132+4 = 136
        bytes4 selector = bytes4(_funcCallData[0:4]);

        // bytes (bytes4 selector + padded address of 32 bytes + uint256 of 32 bytes + offset of bytes32 + length of bytes32 + bytes4 of selector) i.e. 4+32+32+32+32+4 = 136 to end
        bytes calldata data = _funcCallData[4:];

        bool checked;

        if (destinationContract == orderbook) checked = true;

        if (
            destinationContract == positionRouter &&
            (selector == IPositionRouter.createIncreasePosition.selector ||
                selector == IPositionRouter.createIncreasePositionETH.selector)
        ) checked = true;

        if (
            destinationContract == positionRouter &&
            selector == IPositionRouter.createDecreasePosition.selector
        ) {
            address receiver = _decodeCreateDecreasePositionCalldata(data);
            if (receiver == sender) checked = true;
        }

        if (
            destinationContract == referralStorage &&
            selector == IReferralStorage.setTraderReferralCodeByUser.selector
        ) checked = true;

        if (
            destinationContract == router &&
            (selector == IRouter.approvePlugin.selector ||
                selector == IRouter.denyPlugin.selector)
        ) {
            checked = true;
        }

        if (!checked) revert("GMXV1OrderbookValidation: !checked");

        return address(bytes20(_sessionKeyData[:20]));
    }

    function _decodeCreateDecreasePositionCalldata(
        bytes calldata _calldata
    ) internal pure returns (address receiver) {
        (, , , , , receiver, , , , , ) = abi.decode(
            _calldata,
            (
                address[],
                address,
                uint256,
                uint256,
                bool,
                address,
                uint256,
                uint256,
                uint256,
                bool,
                address
            )
        );
    }
}

