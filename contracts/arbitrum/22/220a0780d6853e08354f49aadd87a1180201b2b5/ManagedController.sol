// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import {Initializable} from "./Initializable.sol";
import {OwnableUpgradeable} from "./OwnableUpgradeable.sol";
import "./IFeePolicy.sol";
import "./Multicall.sol";
import "./Calldata.sol";
import "./Gateway.sol";
import "./QuotaStorage.sol";

contract ManagedController is Multicall, Initializable, OwnableUpgradeable, QuotaStorage {
    Gateway public immutable gateway;

    IFeePolicy public feePolicy;
    bool public quotaStorageDisabled; // might possibly disable in L1 if gas is too costly
    mapping(address => bool) public isOperator;

    event FeePolicyChanged(address indexed feePolicy);
    event OperatorChanged(address indexed account, bool isOperator);

    constructor(address _gateway) {
        gateway = Gateway(_gateway);
    }

    function initialize() external initializer {
        __Ownable_init();
    }

    /// @notice Execute a charge. Can only be called by whitelisted operator.
    function charge(Quota memory quota, bytes memory quotaSignature, uint160 amount) public {
        require(isOperator[msg.sender], "not operator");

        if (!quotaStorageDisabled) _storeQuota(quota);

        address destination = address(uint160(uint256(quota.controllerRefId)));
        gateway.charge({
            quota: quota,
            quotaSignature: quotaSignature,
            recipient: destination,
            amount: amount,
            fees: address(feePolicy) == address(0) ? new Fee[](0) : feePolicy.getFees(quota, amount, msg.sender),
            extraEventData: abi.encode(msg.sender)
        });
    }

    /// @dev Note that this is the on-chain status only. Off-chain the product owner can decide not to charge
    /// even if the on-chain status says the quota is "pending next charge".
    function getQuotaStatus(Quota memory quota) public view returns (QuotaStatus status) {
        return gateway.getQuotaStatus(quota);
    }

    // ----- admin functions -----

    function setOperator(address account, bool _isOperator) external onlyOwner {
        isOperator[account] = _isOperator;
        emit OperatorChanged(account, _isOperator);
    }

    function setFeePolicy(address newFeePolicy) external onlyOwner {
        feePolicy = IFeePolicy(newFeePolicy);
        emit FeePolicyChanged(newFeePolicy);
    }

    function setQuotaStorageDisabled(bool disabled) external onlyOwner {
        quotaStorageDisabled = disabled;
    }

    // ----- packed calldata -----

    /// @notice Execute charge with packed calldata
    function charge__packedData() external {
        _unpackAndCharge(CalldataCursor(4, msg.data.length));
    }

    /// @notice Execute multiple charges with packed calldata
    function chargeBatch__packedData() external {
        CalldataCursor memory cursor = CalldataCursor(4, msg.data.length);
        uint256 count = cursor.shiftUint8();
        for (uint256 i = 0; i < count; i++) {
            _unpackAndCharge(cursor);
        }
    }

    function _unpackAndCharge(CalldataCursor memory cursor) internal {
        uint256 flags = cursor.shiftUint8();
        bool useFullQuotaData = (flags & 1) != 0; //    mask: 0b00000001
        bool use2612Permit = (flags & 2) != 0; //       mask: 0b00000010
        bool useDAIPermit = (flags & 4) != 0; //        mask: 0b00000100
        bool usePermitAmount = (flags & 8) != 0; //     mask: 0b00001000
        bool useChargeAmount = (flags & 16) != 0; //    mask: 0b00010000

        Quota memory quota;
        if (useFullQuotaData) {
            address payer = cursor.shiftAddress();
            quota = Quota({
                payer: payer,
                payerNonce: gateway.payerNonces(payer),
                token: cursor.shiftAddress(),
                amount: cursor.shiftUint160(),
                startTime: cursor.shiftUint40(),
                endTime: cursor.shiftUint40(),
                interval: cursor.shiftUint40(),
                chargeWindow: cursor.shiftUint40(),
                controller: address(this),
                controllerRefId: cursor.shiftBytes32()
            });
        } else {
            quota = QuotaStorage.getQuotaById(cursor.shiftUint24());
        }

        if (use2612Permit) {
            permitERC20({
                token: quota.token,
                owner: quota.payer,
                spender: address(gateway),
                value: usePermitAmount ? cursor.shiftUint160() : type(uint256).max,
                deadline: cursor.shiftUint32(),
                v: cursor.shiftUint8(),
                r: cursor.shiftBytes32(),
                s: cursor.shiftBytes32()
            });
        } else if (useDAIPermit) {
            permitDAI({
                dai: quota.token,
                owner: quota.payer,
                spender: address(gateway),
                deadline: cursor.shiftUint32(),
                v: cursor.shiftUint8(),
                r: cursor.shiftBytes32(),
                s: cursor.shiftBytes32()
            });
        }

        uint160 amount = useChargeAmount ? cursor.shiftUint160() : quota.amount;
        bytes memory quotaSignature = useFullQuotaData ? cursor.shiftBytes(cursor.shiftUint8()) : new bytes(0);

        charge(quota, quotaSignature, amount);
    }
}

