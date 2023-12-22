//SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IERC20} from "./IERC20.sol";
import {ReentrancyGuardUpgradeable} from "./ReentrancyGuardUpgradeable.sol";
import {IOFT} from "./IOFT.sol";

import {LzAppSend} from "./LzAppSend.sol";
import {ILayerZeroEndpoint} from "./ILayerZeroEndpoint.sol";
import {ExcessivelySafeCall} from "./ExcessivelySafeCall.sol";
import {BytesLib} from "./BytesLib.sol";

contract MultichainDeposit is LzAppSend, ReentrancyGuardUpgradeable {
    using ExcessivelySafeCall for address;
    using BytesLib for bytes;

    // packet type
    uint16 public constant PT_SEND_AND_CALL = 1;
    uint16 public destChainId;

    IERC20 public constant AURA = IERC20(0x1509706a6c66CA549ff0cB464de88231DDBe213B);
    address public multichainReceiver;

    /* -------------------------------------------------------------------------- */
    /*                                    INIT                                    */
    /* -------------------------------------------------------------------------- */
    function initialize(address _multichainReceiver, address _lzEndpoint, uint16 _destChainId) external initializer {
        __Ownable_init();
        __ReentrancyGuard_init();

        multichainReceiver = _multichainReceiver;
        lzEndpoint = ILayerZeroEndpoint(_lzEndpoint);
        destChainId = _destChainId;
    }

    /* -------------------------------------------------------------------------- */
    /*                                    PUBLIC                                  */
    /* -------------------------------------------------------------------------- */
    function estimateSendAndCallFee(address _user, uint256 _amount, bytes calldata _adapterParams)
        public
        view
        returns (uint256 nativeFee, uint256 zroFee)
    {
        // mock the payload for sendAndCall()
        bytes memory lzPayload = abi.encode(_user, _amount);
        return lzEndpoint.estimateFees(destChainId, address(this), lzPayload, false, _adapterParams);
    }

    /* -------------------------------------------------------------------------- */
    /*                                  EXTERNAL                                  */
    /* -------------------------------------------------------------------------- */
    function multiChainDeposits(
        address _receiver,
        uint256 _amount,
        bytes calldata _auraAdapterParams,
        bytes calldata _adapterParams
    ) external payable nonReentrant {
        address thisAddress = address(this);

        AURA.transferFrom(msg.sender, thisAddress, _amount);

        address zeroAddress = address(0);
        address aura = address(AURA);
        AURA.approve(aura, _amount);

        // Bridge Aura to mainnet
        IOFT(aura).sendFrom{value: msg.value}(
            thisAddress,
            destChainId,
            abi.encodePacked(multichainReceiver),
            _amount,
            payable(thisAddress),
            zeroAddress,
            _auraAdapterParams
        );

        // Send zero layer msg to mainnet receiver contract
        _sendAndCall(_receiver, _amount, thisAddress, zeroAddress, _adapterParams);
    }

    function lzReceive(uint16, bytes calldata, uint64, bytes calldata) external override {}

    receive() external payable {}

    /* -------------------------------------------------------------------------- */
    /*                                    PRIVATE                                 */
    /* -------------------------------------------------------------------------- */

    function _sendAndCall(
        address _user,
        uint256 _amount,
        address thisAddress,
        address _zroPaymentAddress,
        bytes calldata _adapterParams
    ) private {
        (uint256 nativeFee,) = estimateSendAndCallFee(_user,_amount, _adapterParams);
        _checkGasLimit(destChainId, PT_SEND_AND_CALL, _adapterParams, nativeFee);

        bytes memory lzPayload = abi.encode(_user, _amount);
        _lzSend(
            destChainId,
            lzPayload,
            multichainReceiver,
            payable(_user),
            _zroPaymentAddress,
            _adapterParams,
            thisAddress.balance
        );

        emit CrossChainDeposit(destChainId, _user, _amount);
    }

    function _checkGasLimit(uint16 _dstChainId, uint16 _type, bytes memory _adapterParams, uint256 _extraGas)
        internal
        view
        override
    {
        uint256 providedGasLimit = _getGasLimit(_adapterParams);
        uint256 minGasLimit = minDstGasLookup[_dstChainId][_type];
        if (minGasLimit > 0) {
            require(providedGasLimit >= minGasLimit, "LzApp: dst gas provided is too low");
        }
        require(address(this).balance >= _getGasLimit(_adapterParams) + _extraGas, "LzApp: gas provided is too low");
    }

    /* -------------------------------------------------------------------------- */
    /*                                 ONLY OWNER                                 */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Moves assets from the strategy to `_to`
     * @param _assets An array of IERC20 compatible tokens to move out from the strategy
     * @param _withdrawNative `true` if we want to move the native asset from the strategy
     */
    function emergencyWithdraw(address _to, address[] memory _assets, bool _withdrawNative) external onlyOwner {
        uint256 assetsLength = _assets.length;
        for (uint256 i = 0; i < assetsLength; i++) {
            IERC20 asset = IERC20(_assets[i]);
            uint256 assetBalance = asset.balanceOf(address(this));

            if (assetBalance > 0) {
                // Transfer the ERC20 tokens
                asset.transfer(_to, assetBalance);
            }

            unchecked {
                ++i;
            }
        }

        uint256 nativeBalance = address(this).balance;

        // Nothing else to do
        if (_withdrawNative && nativeBalance > 0) {
            // Transfer the native currency
            (bool sent,) = payable(_to).call{value: nativeBalance}("");
            if (!sent) {
                revert FailSendETH();
            }
        }

        emit EmergencyWithdrawal(msg.sender, _to, _assets, _withdrawNative ? nativeBalance : 0);
    }

    function setMultichainReceiver(address _multichainReceiver) external onlyOwner {
        multichainReceiver = _multichainReceiver;
    }

    function setDstChainId(uint16 _destChainId) external onlyOwner {
        destChainId = _destChainId;
    }

    /* -------------------------------------------------------------------------- */
    /*                                   EVENTS                                   */
    /* -------------------------------------------------------------------------- */

    event CrossChainDeposit(uint16 _dstChainId, address _from, uint256 _amount);
    event EmergencyWithdrawal(address indexed caller, address indexed receiver, address[] tokens, uint256 nativeBalanc);

    /* -------------------------------------------------------------------------- */
    /*                                    ERRORS                                  */
    /* -------------------------------------------------------------------------- */

    error FailSendETH();
}

