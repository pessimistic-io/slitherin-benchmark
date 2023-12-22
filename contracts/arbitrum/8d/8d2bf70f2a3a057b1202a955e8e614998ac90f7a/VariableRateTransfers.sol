// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./IERC20Metadata.sol";
import "./Ownable.sol";
import "./Initializable.sol";
import "./Pausable.sol";

import "./IVariableRateTransfers.sol";
import "./Access.sol";
import "./CommonState.sol";
import "./ProcessorManagerV2.sol";
import "./TokenManagerV2.sol";
import "./FeeMath.sol";
import "./TokenMath.sol";
import "./SigUtils.sol";

contract VariableRateTransfers is
    IVariableRateTransfers,
    Ownable,
    Initializable,
    CommonState,
    ProcessorManagerV2,
    TokenManagerV2,
    SigUtils,
    Pausable
{
    address public inboundTreasury;
    address public outboundTreasury;
    address public certifiedSigner;
    mapping(uint256 => bool) public transfers;
    SecurityLevel public securityLevel;

    event TransferProcessed(
        address indexed caller,
        string id,
        bool success,
        bool inbound,
        address token,
        address endUser,
        uint256 amount,
        uint256 processingFee,
        bytes err
    );

    event SecurityLevelUpdated(
        address indexed caller,
        SecurityLevel oldSecurityLevel,
        SecurityLevel newSecurityLevel
    );

    event OperatorAddressUpdated(
        address indexed caller,
        OperatorAddress indexed account,
        address oldAddress,
        address newAddress
    );

    function initialize(
        ProcessorManagerInitParams calldata processorManagerInitParams_,
        TokenManagerInitParams calldata tokenManagerInitParams_,
        OperatorInitParams calldata operatorInitParams_,
        SecurityLevel securityLevel_,
        CommonStateInitParams calldata commonStateInitParams_,
        address multiRoleGrantee_
    ) external initializer {
        _transferOwnership(msg.sender);
        __Access_init(multiRoleGrantee_);
        __CommonState_init(
            commonStateInitParams_.factory,
            commonStateInitParams_.WETH
        );
        __ProcessorManager_init(processorManagerInitParams_);
        __TokenManager_init(
            tokenManagerInitParams_.acceptedTokens,
            tokenManagerInitParams_.chainlinkAggregators
        );
        _setOperatorAddress(
            address(0),
            OperatorAddress.INBOUND_TREASURY,
            operatorInitParams_.inboundTreasury
        );
        _setOperatorAddress(
            address(0),
            OperatorAddress.OUTBOUND_TREASURY,
            operatorInitParams_.outboundTreasury
        );
        _setOperatorAddress(
            address(0),
            OperatorAddress.SIGNER,
            operatorInitParams_.signer
        );

        _setSecurityLevel(address(0), securityLevel_);
    }

    /*************************************************/
    /*************   EXTERNAL  FUNCTIONS   *************/
    /*************************************************/

    // TODO non-reentrant (?)
    function processTransfers(TransferParams[] calldata transfers_)
        external
        onlyValidProcessorExt
        whenNotPaused
    {
        if (securityLevel == SecurityLevel.DIRECT) {
            _processDirectTransfers(transfers_);
        } else {
            _processPlatformTransfers(transfers_);
        }
    }

    function pause() external onlyOperator {
        _pause();
    }

    function unpause() external onlyOperator {
        _unpause();
    }

    function setOperatorAddress(OperatorAddress account_, address addr_)
        external
        onlyOperator
    {
        _setOperatorAddress(msg.sender, account_, addr_);
    }

    function setSecurityLevel(SecurityLevel securityLevel_)
        external
        onlyGovernor
    {
        _setSecurityLevel(msg.sender, securityLevel_);
    }

    function processTransfer(
        Transfer calldata transfer_,
        Signature calldata signature_,
        bool inbound_,
        address processor_
    ) external returns (uint256 amount, uint256 processingFee) {
        require(msg.sender == address(this), "LC:SELF_ONLY");

        require(tokenInfo[transfer_.token].accepted > 0, "LC:INVALID_TOKEN");

        /* Validate Signature */
        address transferSigner = _getSigner(transfer_, signature_);

        require(transferSigner == certifiedSigner, "LC:INVALID_SIGNER");

        /* Validate Transfer Uniqueness */
        uint256 transferHash = _hashTransfer(transfer_);

        require(!transfers[transferHash], "LC:TRANSFER_ALREADY_PROCESSED");
        transfers[transferHash] = true;

        (uint256 exchangeRate, uint8 exchangeRatedecimals) = _getTokenToUsdRate(
            transfer_.token
        );

        uint256 tokenDecimals = IERC20Metadata(transfer_.token).decimals();

        /* Convert USD Amounts to Given Token */
        amount = transfer_.usd
            ? TokenMath.convertUsdToTokenAmount(
                transfer_.amount,
                exchangeRate,
                exchangeRatedecimals,
                tokenDecimals
            )
            : transfer_.amount;

        /* Process Fee */
        uint256 baseFeeTokenAmt = TokenMath.convertUsdToTokenAmount(
            baseFee,
            exchangeRate,
            exchangeRatedecimals,
            tokenDecimals
        );
        processingFee = FeeMath.calculateProcessingFee(
            baseFeeTokenAmt,
            variableFee,
            amount
        );

        amount = inbound_ ? amount - processingFee : amount;

        if (processingFee > 0) {
            IERC20Metadata(transfer_.token).transferFrom(
                transfer_.from,
                processor_,
                processingFee
            );
        }

        /* Execute Transfer */
        IERC20Metadata(transfer_.token).transferFrom(
            transfer_.from,
            transfer_.to,
            amount
        );
    }

    function _processDirectTransfers(TransferParams[] calldata transfers_)
        internal
    {
        bool success;
        bytes memory returnData;
        bytes memory err;
        bool inbound;
        address endUser;
        uint256 _amount;
        uint256 _processingFee;

        for (uint256 i = 0; i < transfers_.length; i++) {
            if (transfers_[i].data.to == inboundTreasury) {
                inbound = true;
                endUser = transfers_[i].data.from;

                (success, returnData) = address(this).call(
                    abi.encodeWithSelector(
                        this.processTransfer.selector,
                        transfers_[i].data,
                        transfers_[i].signature,
                        inbound,
                        msg.sender
                    )
                );
            } else if (transfers_[i].data.from == outboundTreasury) {
                inbound = false;
                endUser = transfers_[i].data.to;

                (success, returnData) = address(this).call(
                    abi.encodeWithSelector(
                        this.processTransfer.selector,
                        transfers_[i].data,
                        transfers_[i].signature,
                        inbound,
                        msg.sender
                    )
                );
            } else {
                success = false;
                returnData = bytes("LC:INVALID_TO_FROM_ADDRESS");
            }

            if (success) {
                (_amount, _processingFee) = abi.decode(
                    returnData,
                    (uint256, uint256)
                );
                err = bytes("");
            } else {
                err = returnData;
                _amount = transfers_[i].data.amount;
                _processingFee = 0;
            }

            emit TransferProcessed(
                msg.sender,
                transfers_[i].data.id,
                success,
                inbound,
                transfers_[i].data.token,
                endUser,
                _amount,
                _processingFee,
                err
            );
        }
    }

    function _processPlatformTransfers(TransferParams[] calldata transfers_)
        internal
    {
        bool success;
        bytes memory returnData;
        bytes memory err;
        uint256 _amount;
        uint256 _processingFee;

        for (uint256 i = 0; i < transfers_.length; i++) {
            (success, returnData) = address(this).call(
                abi.encodeWithSelector(
                    this.processTransfer.selector,
                    transfers_[i].data,
                    transfers_[i].signature,
                    true,
                    msg.sender
                )
            );

            if (success) {
                (_amount, _processingFee) = abi.decode(
                    returnData,
                    (uint256, uint256)
                );
                err = bytes("");
            } else {
                err = returnData;
                _amount = transfers_[i].data.amount;
                _processingFee = 0;
            }

            emit TransferProcessed(
                msg.sender,
                transfers_[i].data.id,
                success,
                true,
                transfers_[i].data.token,
                transfers_[i].data.from,
                _amount,
                _processingFee,
                err
            );
        }
    }

    function _hashTransfer(Transfer calldata transfer_)
        internal
        pure
        returns (uint256 transferHash)
    {
        transferHash = uint256(
            keccak256(
                abi.encode(
                    transfer_.invoiceId,
                    transfer_.from,
                    transfer_.to,
                    transfer_.token,
                    transfer_.amount,
                    transfer_.usd
                )
            )
        );
    }

    function _setOperatorAddress(
        address sender_,
        OperatorAddress account_,
        address addr_
    ) internal {
        if (account_ == OperatorAddress.INBOUND_TREASURY) {
            emit OperatorAddressUpdated(
                sender_,
                account_,
                inboundTreasury,
                addr_
            );
            inboundTreasury = addr_;
        } else if (account_ == OperatorAddress.OUTBOUND_TREASURY) {
            emit OperatorAddressUpdated(
                sender_,
                account_,
                outboundTreasury,
                addr_
            );
            outboundTreasury = addr_;
        } else if (account_ == OperatorAddress.SIGNER) {
            emit OperatorAddressUpdated(
                sender_,
                account_,
                certifiedSigner,
                addr_
            );
            certifiedSigner = addr_;
        } else {
            revert("LC:INVALID_ACCOUNT_NAME");
        }
    }

    function _setSecurityLevel(address sender_, SecurityLevel securityLevel_)
        private
    {
        emit SecurityLevelUpdated(sender_, securityLevel, securityLevel_);
        securityLevel = securityLevel_;
    }
}

