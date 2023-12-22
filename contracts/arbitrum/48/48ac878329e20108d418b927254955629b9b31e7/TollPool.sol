// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.9;

import { IERC20 } from "./IERC20.sol";
import { OwnableUpgradeableSafe } from "./OwnableUpgradeableSafe.sol";
import { AddressArray } from "./AddressArray.sol";
import { UIntMath } from "./UIntMath.sol";
import { TransferHelper } from "./TransferHelper.sol";
import { IMultiTokenRewardRecipient } from "./IMultiTokenRewardRecipient.sol";

contract TollPool is IMultiTokenRewardRecipient, OwnableUpgradeableSafe {
    using UIntMath for uint256;
    using AddressArray for address[];
    using TransferHelper for IERC20;

    uint256 public constant TOKEN_AMOUNT_LIMIT = 20;

    //**********************************************************//
    //    The below state variables can not change the order    //
    //**********************************************************//

    address public feeTokenPoolDispatcher;
    address[] public feeTokens;

    address public clearingHouse;

    //**********************************************************//
    //    The above state variables can not change the order    //
    //**********************************************************//

    //◥◤◥◤◥◤◥◤◥◤◥◤◥◤◥◤ add state variables below ◥◤◥◤◥◤◥◤◥◤◥◤◥◤◥◤//

    //◢◣◢◣◢◣◢◣◢◣◢◣◢◣◢◣ add state variables above ◢◣◢◣◢◣◢◣◢◣◢◣◢◣◢◣//
    uint256[50] private __gap;

    //
    // EVENTS
    //
    event TokenReceived(address token, uint256 amount);
    event TokenTransferred(address token, uint256 amount);
    event FeeTokenPoolDispatcherSet(address feeTokenPoolDispatcher);
    event FeeTokenAdded(address token);
    event FeeTokenRemoved(address token);

    //
    // MODIFIERS
    //
    modifier onlyClearingHouse() {
        require(_msgSender() == address(clearingHouse), "TP_NCH"); //not clearinghouse
        _;
    }

    //
    // FUNCTIONS
    //
    function initialize(address _clearingHouse) external initializer {
        require(address(_clearingHouse) != address(0), "TP_NCH"); //not clearinghouse
        __Ownable_init();
        clearingHouse = _clearingHouse;
    }

    // this function will be used for upcoming staking system
    function notifyTokenAmount(IERC20, uint256) external pure {
        revert("TP_NSY"); // not supported yet
    }

    function transferToFeeTokenPoolDispatcher() external {
        require(address(feeTokenPoolDispatcher) != address(0), "TP_FDNS"); //feeTokenPoolDispatcher not yet set
        require(feeTokens.length != 0, "TP_FTNS"); //feeTokens not set yet

        bool hasToll;
        for (uint256 i; i < feeTokens.length; i++) {
            address token = feeTokens[i];
            hasToll = transferToDispatcher(IERC20(token)) || hasToll;
        }
        // revert if total fee of all tokens is zero
        require(hasToll, "TP_ZF"); //zero fee
    }

    function setFeeTokenPoolDispatcher(address _feeTokenPoolDispatcher) external onlyOwner {
        require(_feeTokenPoolDispatcher != address(0), "TP_II"); //invalid input
        require(_feeTokenPoolDispatcher != feeTokenPoolDispatcher, "TP_ISC"); //input is the same as the current one
        feeTokenPoolDispatcher = _feeTokenPoolDispatcher;
        emit FeeTokenPoolDispatcherSet(_feeTokenPoolDispatcher);
    }

    function addFeeToken(IERC20 _token) external onlyOwner {
        require(feeTokens.length < TOKEN_AMOUNT_LIMIT, "TP_ETAL"); //exceed token amount limit
        require(feeTokens.add(address(_token)), "TP_II"); //invalid input

        emit FeeTokenAdded(address(_token));
    }

    function removeFeeToken(IERC20 _token) external onlyOwner {
        address removedAddr = feeTokens.remove(address(_token));
        require(address(feeTokenPoolDispatcher) != address(0), "TP_FDNS"); //feeTokenPoolDispatcher not yet set
        require(removedAddr != address(0), "TP_TNE"); //token does not exist
        require(removedAddr == address(_token), "TP_RWT"); //remove wrong token

        if (_token.balanceOf(address(this)) > 0) {
            transferToDispatcher(_token);
        }
        emit FeeTokenRemoved(address(_token));
    }

    //
    // VIEW FUNCTIONS
    //
    function isFeeTokenExisted(IERC20 _token) external view returns (bool) {
        return feeTokens.isExisted(address(_token));
    }

    function getFeeTokenLength() external view returns (uint256) {
        return feeTokens.length;
    }

    //
    // INTERNAL FUNCTIONS
    //
    function transferToDispatcher(IERC20 _token) private returns (bool) {
        uint256 balance = _token.balanceOf(address(this));

        if (balance != 0) {
            //_approve(_token, address(clientBridge), balance);
            _token.safeTransfer(address(feeTokenPoolDispatcher), balance);
            //clientBridge.erc20Transfer(_token, address(feeTokenPoolDispatcherL1), balance);
            emit TokenTransferred(address(_token), balance);
            return true;
        }
        return false;
    }
}

