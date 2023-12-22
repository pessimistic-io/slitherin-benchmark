// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {IERC20} from "./IERC20.sol";
import {IERC20Permit} from "./IERC20Permit.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {ERC721} from "./ERC721.sol";
import {ERC721Enumerable} from "./ERC721Enumerable.sol";
import {IERC165} from "./IERC165.sol";

import {IVault} from "./IVault.sol";
import {IDefii} from "./IDefii.sol";
import {OperatorMixin} from "./OperatorMixin.sol";
import {DefiiStatus, DefiiStatusLogic} from "./DefiiStatusLogic.sol";

contract Vault is ERC721Enumerable, OperatorMixin, IVault {
    using SafeERC20 for IERC20;
    using DefiiStatusLogic for uint256;

    struct DefiiInfo {
        address defii;
        uint16 weight; // bps
    }

    uint256 constant OPERATOR_POSITION_ID = 0;

    address public immutable notion;
    uint256 public immutable numDefiis;
    uint256 immutable ALL_DEFIIS_ENTERED_MASK;

    mapping(uint256 positionId => mapping(address token => uint256 balance))
        public funds;
    mapping(uint256 positionId => uint256 status) _positionStatusMask;
    mapping(uint256 positionId => uint256 depositAmount) _enterAmount;

    mapping(address => uint256) public defiiWeight;
    mapping(address => uint256) _defiiIndex;
    address[] _defiis;

    constructor(
        DefiiInfo[] memory defiiConfig,
        string memory vaultName,
        string memory vaultSymbol
    ) ERC721(vaultName, vaultSymbol) {
        _mint(msg.sender, OPERATOR_POSITION_ID);

        numDefiis = defiiConfig.length;
        require(numDefiis > 0);

        notion = IDefii(defiiConfig[0].defii).notion();

        DefiiInfo memory defiiInfo;
        for (uint256 i = 0; i < numDefiis; i++) {
            defiiInfo = defiiConfig[i];
            require(notion == IDefii(defiiInfo.defii).notion());
            require(defiiInfo.weight > 0);

            defiiWeight[defiiInfo.defii] = defiiInfo.weight;
            _defiiIndex[defiiInfo.defii] = i;
            _defiis.push(defiiInfo.defii);
        }

        ALL_DEFIIS_ENTERED_MASK = DefiiStatusLogic
            .calculateAllDefiisEnteredMask(numDefiis);
    }

    function depositWithPermit(
        address token,
        uint256 amount,
        uint256 operatorFeeAmount,
        uint256 deadline,
        uint8 permitV,
        bytes32 permitR,
        bytes32 permitS
    ) external {
        IERC20Permit(token).permit(
            msg.sender,
            address(this),
            amount,
            deadline,
            permitV,
            permitR,
            permitS
        );
        uint256 positionId = _getPositionId(msg.sender, true);

        _deposit(positionId, token, amount);
        _payOperatorFee(positionId, token, operatorFeeAmount);

        if (token == notion) {
            _resetEnterAmount(positionId);
        }
    }

    function deposit(
        address token,
        uint256 amount,
        uint256 operatorFeeAmount
    ) external {
        uint256 positionId = _getPositionId(msg.sender, true);

        _deposit(positionId, token, amount);
        _payOperatorFee(positionId, token, operatorFeeAmount);

        if (token == notion) {
            _resetEnterAmount(positionId);
        }
    }

    function depositToPosition(
        uint256 positionId,
        address token,
        uint256 amount
    ) external {
        _deposit(positionId, token, amount);
    }

    function _deposit(
        uint256 positionId,
        address token,
        uint256 amount
    ) internal {
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        _changeBalance(positionId, token, amount, true);
    }

    function payOperatorFee(address token, uint256 operatorFeeAmount) external {
        _payOperatorFee(
            _getPositionId(msg.sender, false),
            token,
            operatorFeeAmount
        );
    }

    function withdraw(
        address token,
        uint256 amount,
        uint256 positionId
    ) external {
        if (_isDefii(token)) revert UseWithdrawLiquidity(token);
        if (token == notion) _validatePostionNotProcessing(positionId);

        address tokenOwner = ownerOf(positionId);
        _operatorCheckApproval(tokenOwner);
        _changeBalance(positionId, token, amount, false);
        IERC20(token).safeTransfer(tokenOwner, amount);
    }

    function withdrawLiquidityFromDefii(
        address defii,
        IDefii.Instruction[] calldata instructions
    ) external payable validateDefii(defii) {
        uint256 positionId = _getPositionId(msg.sender, false);
        uint256 lpAmount = funds[positionId][defii];
        _changeBalance(positionId, defii, lpAmount, false);

        IDefii(defii).withdrawLiquidity(msg.sender, lpAmount, instructions);
    }

    function enterDefii(
        address defii,
        uint256 positionId,
        IDefii.Instruction[] calldata instructions
    )
        external
        payable
        validateDefii(defii)
        operatorCheckApproval(ownerOf(positionId))
    {
        _changeDefiiStatus(positionId, defii, DefiiStatus.ENTER_STARTED);

        uint256 amount = calculateEnterDefiiAmount(positionId, defii);
        _changeBalance(positionId, notion, amount, false);
        IERC20(notion).safeIncreaseAllowance(defii, amount);
        IDefii(defii).enter{value: msg.value}(amount, positionId, instructions);
    }

    function enterCallback(
        uint256 positionId,
        uint256 shares
    ) external validateDefii(msg.sender) {
        _changeBalance(positionId, msg.sender, shares, true);
        _changeDefiiStatus(positionId, msg.sender, DefiiStatus.ENTERED);
    }

    function exitDefii(
        address defii,
        uint256 positionId,
        uint256 percentage, // bps
        IDefii.Instruction[] calldata instructions
    )
        external
        payable
        validateDefii(defii)
        operatorCheckApproval(ownerOf(positionId))
    {
        _changeDefiiStatus(positionId, defii, DefiiStatus.EXIT_STARTED);

        uint256 shares = (funds[positionId][defii] * percentage) / 1e4;
        _changeBalance(positionId, defii, shares, false);
        IDefii(defii).exit{value: msg.value}(shares, positionId, instructions);
    }

    function exitCallback(
        uint256 positionId
    ) external validateDefii(msg.sender) {
        _changeDefiiStatus(positionId, msg.sender, DefiiStatus.NOT_ENTERED);
    }

    function getDefiis() external view returns (address[] memory) {
        return _defiis;
    }

    function getPositionStatus(
        uint256 positionId
    )
        external
        view
        returns (bool isProcessing, DefiiStatus[] memory defiiStatuses)
    {
        defiiStatuses = new DefiiStatus[](numDefiis);

        uint256 statusMask = _positionStatusMask[positionId];
        for (uint256 defiiIndex = 0; defiiIndex < numDefiis; defiiIndex++) {
            defiiStatuses[defiiIndex] = statusMask.defiiStatus(defiiIndex);
        }

        return (
            statusMask.isPositionProcessing(ALL_DEFIIS_ENTERED_MASK),
            defiiStatuses
        );
    }

    function calculateEnterDefiiAmount(
        uint256 positionId,
        address defii
    ) public view returns (uint256) {
        return (_enterAmount[positionId] * defiiWeight[defii]) / 1e4;
    }

    function _resetEnterAmount(uint256 positionId) internal {
        _validatePostionNotProcessing(positionId);
        _enterAmount[positionId] = funds[positionId][notion];
    }

    function _getPositionId(
        address user,
        bool mint
    ) internal returns (uint256) {
        if (balanceOf(user) == 0 && mint) {
            uint256 positionId = totalSupply();
            _mint(user, positionId);
            return positionId;
        }
        return tokenOfOwnerByIndex(user, 0);
    }

    function _changeBalance(
        uint256 positionId,
        address token,
        uint256 amount,
        bool increase
    ) internal {
        if (amount == 0) return;

        if (increase) {
            funds[positionId][token] += amount;
        } else {
            funds[positionId][token] -= amount;
        }

        emit BalanceChanged(positionId, token, amount, increase);
    }

    function _changeDefiiStatus(
        uint256 positionId,
        address defii,
        DefiiStatus newStatus
    ) internal {
        uint256 statusMask = _positionStatusMask[positionId];
        uint256 defiiIndex = _defiiIndex[defii];
        DefiiStatus currentStatus = statusMask.defiiStatus(defiiIndex);

        if (!DefiiStatusLogic.validateNewStatus(currentStatus, newStatus)) {
            revert CantChangeDefiiStatus(
                currentStatus,
                newStatus,
                statusMask.isPositionProcessing(ALL_DEFIIS_ENTERED_MASK)
            );
        }

        uint256 newStatusMask;
        if (statusMask.isPositionProcessing(ALL_DEFIIS_ENTERED_MASK)) {
            newStatusMask = statusMask.setStatus(defiiIndex, newStatus);
        } else {
            // If position not processing (eg all defiis entered/exited)
            // we can reset their statuses.
            if (newStatus == DefiiStatus.ENTER_STARTED) {
                newStatusMask = uint256(0).setStatus(defiiIndex, newStatus);
            } else {
                newStatusMask = ALL_DEFIIS_ENTERED_MASK.setStatus(
                    defiiIndex,
                    newStatus
                );
            }
        }

        _positionStatusMask[positionId] = newStatusMask;
        emit DefiiStatusChanged(positionId, defii, newStatus, currentStatus);
    }

    function _payOperatorFee(
        uint256 positionId,
        address token,
        uint256 operatorFeeAmount
    ) internal {
        _changeBalance(positionId, token, operatorFeeAmount, false);
        _changeBalance(OPERATOR_POSITION_ID, token, operatorFeeAmount, true);
    }

    modifier validateDefii(address defii) {
        _validateDefii(defii);
        _;
    }

    function _validateDefii(address defii) internal view {
        if (!_isDefii(defii)) {
            revert UnsupportedDefii(defii);
        }
    }

    function _isDefii(address defii) internal view returns (bool) {
        return defiiWeight[defii] > 0;
    }

    function _validatePostionNotProcessing(uint256 positionId) internal view {
        if (_isPositonProcessing(positionId)) {
            revert PositionProcessing();
        }
    }

    function _isPositonProcessing(
        uint256 positionId
    ) internal view returns (bool) {
        uint256 statusMask = _positionStatusMask[positionId];
        return statusMask.isPositionProcessing(ALL_DEFIIS_ENTERED_MASK);
    }
}

