// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.9;

import "./OwnableUpgradeable.sol";
import "./SafeMathUpgradeable.sol";
//import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "./IFuturXGatewayStorage.sol";
import "./IVault.sol";

import {Errors} from "./Errors.sol";
import "./IFuturXGateway.sol";

contract FuturXGatewayStorage is IFuturXGatewayStorage, OwnableUpgradeable {
    using SafeMathUpgradeable for uint256;

    address public futurXGateway;

    mapping(address => uint256) public increasePositionsIndex;
    mapping(bytes32 => IncreasePositionRequest) public increasePositionRequests;
    bytes32[] public increasePositionRequestKeys;

    mapping(address => uint256) public decreasePositionsIndex;
    mapping(bytes32 => DecreasePositionRequest) public decreasePositionRequests;
    bytes32[] public decreasePositionRequestKeys;

    mapping(address => uint256) public updateCollateralIndex;
    mapping(bytes32 => UpdateCollateralRequest) public updateCollateralRequests;
    bytes32[] public updateCollateralRequestKeys;

    mapping(bytes32 => bytes32) public tpslRequests;

    modifier onlyHandler() {
        _validate(isHandler[msg.sender], Errors.FGWS_CALLER_NOT_WHITELISTED);
        _;
    }

    function initialize(address _futurXGateway) public initializer {
        __Ownable_init();
        futurXGateway = _futurXGateway;
    }

    function getPendingCollateral(
        address _account,
        address _indexToken
    ) public view returns (PendingCollateral memory) {
        bytes32 key = _getPendingCollateralKey(_account, _indexToken);
        return pendingCollaterals[key];
    }

    function clearPendingCollateral(
        address _account,
        address _indexToken
    ) public onlyHandler {
        bytes32 key = _getPendingCollateralKey(_account, _indexToken);
        pendingCollaterals[key].count = 0;
        pendingCollaterals[key].collateral = address(0);
    }

    function updatePendingCollateral(
        UpPendingCollateralParam memory param
    ) public onlyHandler returns (bytes32) {
        bytes32 key = _getPendingCollateralKey(param.account, param.indexToken);
        PendingCollateral storage data = pendingCollaterals[key];
        // Operation = 1 means increase count
        if (param.op == 1) {
            if (data.count > 0) {
                _validate(
                    data.collateral == param.collateralToken,
                    Errors.FGWS_PENDING_COLLATERAL_MISMATCHED
                );
            } else {
                data.collateral = param.collateralToken;
            }
            data.count++;
        }

        // Operation = 2 means decrease count
        if (param.op == 2) {
            if (data.count > 0) {
                data.count--;
            }
            if (data.count == 0) {
                data.collateral = address(0);
            }
        }
        // TODO: Don't know why `storage` alone doesn't persist here
        pendingCollaterals[key] = data;
        return key;
    }

    function storeIncreasePositionRequest(
        IncreasePositionRequest memory _request
    ) public onlyHandler returns (uint256, bytes32) {
        address account = _request.account;
        uint256 index = increasePositionsIndex[account].add(1);
        increasePositionsIndex[account] = index;
        bytes32 key = _getRequestKey(account, index, OpCode.IncreasePosition);

        increasePositionRequests[key] = _request;
        increasePositionRequestKeys.push(key);

        return (index, key);
    }

    function getIncreasePositionRequest(
        bytes32 _key
    ) public view returns (IncreasePositionRequest memory request) {
        request = increasePositionRequests[_key];
    }

    function getIncreasePositionRequestAndManager(
        bytes32 _key
    ) public view returns (IncreasePositionRequest memory request, address positionManager) {
        request = increasePositionRequests[_key];
        positionManager = IFuturXGateway(futurXGateway).coreManagers(request.indexToken);
    }

    function getDeleteIncreasePositionRequest(
        bytes32 _key
    ) public onlyHandler returns (IncreasePositionRequest memory request) {
        request = increasePositionRequests[_key];
        _validate(
            request.account != address(0),
            Errors.FGWS_MISSING_ACCOUNT_01
        );
        _deleteIncreasePositionRequests(_key);
    }

    function getUpdateOrDeleteIncreasePositionRequest(
        bytes32 _key,
        uint256 amountInToken,
        bool isExecutedFully,
        IVault vault,
        uint16 leverage
    ) public onlyHandler returns (IncreasePositionRequest memory request) {
        request = increasePositionRequests[_key];
        _validate(
            request.account != address(0),
            Errors.FGWS_MISSING_ACCOUNT_02
        );

        if (isExecutedFully) {
            delete increasePositionRequests[_key];
        } else {
            uint256 amountAdjust = vault.adjustDecimalToToken(
                request.indexToken,
                amountInToken / leverage
            );
            amountAdjust = vault.convert(
                request.indexToken,
                request.path[0],
                amountAdjust
            );
            uint256 feeExecute = request.feeUsd.mul(amountAdjust).div(request.amountInToken);
            increasePositionRequests[_key].feeUsd = request.feeUsd.sub(feeExecute);
            request.feeUsd = feeExecute;
            increasePositionRequests[_key].amountInToken = request
                .amountInToken
                .sub(amountAdjust);
            request.amountInToken = amountAdjust;
        }
    }

    function storeDecreasePositionRequest(
        DecreasePositionRequest memory _request
    ) public onlyHandler returns (uint256, bytes32) {
        address account = _request.account;
        uint256 index = decreasePositionsIndex[account].add(1);
        decreasePositionsIndex[account] = index;
        bytes32 key = _getRequestKey(account, index, OpCode.DecreasePosition);

        decreasePositionRequests[key] = _request;
        decreasePositionRequestKeys.push(key);

        return (index, key);
    }

    function getDecreasePositionRequest(
        bytes32 _key
    ) public view returns (DecreasePositionRequest memory request) {
        request = decreasePositionRequests[_key];
    }

    function getDecreasePositionRequestAndManager(
        bytes32 _key
    ) public view returns (DecreasePositionRequest memory request, address positionManager) {
        request = decreasePositionRequests[_key];
        positionManager = IFuturXGateway(futurXGateway).coreManagers(request.indexToken);
    }

    function getDeleteDecreasePositionRequest(
        bytes32 _key
    ) public onlyHandler returns (DecreasePositionRequest memory request) {
        request = decreasePositionRequests[_key];
        _validate(
            request.account != address(0),
            Errors.FGWS_MISSING_ACCOUNT_03
        );
        _deleteDecreasePositionRequests(_key);
    }

    function getUpdateOrDeleteDecreasePositionRequest(
        bytes32 _key,
        uint256 quantity,
        bool isExecutedFully
    ) public onlyHandler returns (DecreasePositionRequest memory request) {
        request = decreasePositionRequests[_key];
        _validate(
            request.account != address(0),
            Errors.FGWS_MISSING_ACCOUNT_02
        );

        if (isExecutedFully) {
            delete decreasePositionRequests[_key];
        } else {
            decreasePositionRequests[_key].sizeDeltaToken =
                request.sizeDeltaToken -
                quantity;
            request.sizeDeltaToken = quantity;
        }
    }

    function deleteDecreasePositionRequest(bytes32 _key) public onlyHandler {
        _deleteDecreasePositionRequests(_key);
    }

    function storeUpdateCollateralRequest(
        UpdateCollateralRequest memory _request
    ) public onlyHandler returns (uint256, bytes32) {
        address account = _request.account;
        uint256 index = updateCollateralIndex[account].add(1);
        updateCollateralIndex[account] = index;
        bytes32 key = _getRequestKey(account, index, OpCode.UpdateCollateral);

        updateCollateralRequests[key] = _request;
        updateCollateralRequestKeys.push(key);

        return (index, key);
    }

    function getTPSLRequest(
        address _account,
        address _indexToken,
        bool _isHigherPip
    ) external view returns (bytes32) {
        bytes32 key = _getTPSLRequestKey(_account, _indexToken, _isHigherPip);
        return tpslRequests[key];
    }

    function storeTpslRequest(
        address _account,
        address _indexToken,
        bool _isHigherPip,
        bytes32 _decreasePositionRequestKey
    ) public onlyHandler {
        bytes32 key = _getTPSLRequestKey(_account, _indexToken, _isHigherPip);
        tpslRequests[key] = _decreasePositionRequestKey;
    }

    function deleteTpslRequest(
        address _account,
        address _indexToken,
        bool _isHigherPip
    ) public onlyHandler {
        bytes32 key = _getTPSLRequestKey(_account, _indexToken, _isHigherPip);
        _deleteDecreasePositionRequests(tpslRequests[key]);
        _deleteTpslRequests(key);
    }

    function getDeleteUpdateCollateralRequest(
        bytes32 _key
    ) public onlyHandler returns (UpdateCollateralRequest memory request) {
        request = updateCollateralRequests[_key];
        _validate(
            request.account != address(0),
            Errors.FGWS_MISSING_ACCOUNT_04
        );
        _deleteUpdateCollateralRequests(_key);
    }

    function getRequestKey(
        address _account,
        uint256 _index,
        OpCode _op
    ) external view returns (bytes32) {
        return _getRequestKey(_account, _index, _op);
    }

    function getTPSLRequestKey(
        address _account,
        address _indexToken,
        bool _isHigherPip
    ) external pure returns (bytes32) {
        return _getTPSLRequestKey(_account, _indexToken, _isHigherPip);
    }

    function _getRequestKey(
        address _account,
        uint256 _index,
        OpCode _op
    ) private view returns (bytes32) {
        return
            keccak256(abi.encodePacked(_account, _index, _op, address(this)));
    }

    function _getTPSLRequestKey(
        address _account,
        address _indexToken,
        bool _isHigherPip
    ) private pure returns (bytes32) {
        return keccak256(abi.encodePacked(_account, _indexToken, _isHigherPip));
    }

    function _getPendingCollateralKey(
        address _account,
        address _indexToken
    ) private pure returns (bytes32) {
        return keccak256(abi.encodePacked(_account, _indexToken));
    }

    function _deleteIncreasePositionRequests(bytes32 _key) private {
        delete increasePositionRequests[_key];
    }

    function _deleteDecreasePositionRequests(bytes32 _key) private {
        delete decreasePositionRequests[_key];
    }

    function _deleteUpdateCollateralRequests(bytes32 _key) private {
        delete updateCollateralRequests[_key];
    }

    function _deleteTpslRequests(bytes32 _key) private {
        delete tpslRequests[_key];
    }

    /*************************
     ** ONLY OWNER FUNCTION **
     *************************/
    function setFuturXGateway(address _address) external onlyOwner {
        futurXGateway = _address;
    }

    function _validate(bool _condition, string memory _errorCode) private view {
        require(_condition, _errorCode);
    }

    function setHandler(address _handler, bool _isHandler) external onlyOwner {
        isHandler[_handler] = _isHandler;
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[49] private __gap;
    mapping(bytes32 => PendingCollateral) pendingCollaterals;
    mapping(address => bool) public isHandler;
}

