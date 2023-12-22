// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20} from "./IERC20.sol";
import {IERC20Permit} from "./IERC20Permit.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {ERC721} from "./ERC721.sol";
import {ERC721Enumerable} from "./ERC721Enumerable.sol";

import {IVault} from "./IVault.sol";
import {IDefii} from "./IDefii.sol";
import {OperatorMixin} from "./OperatorMixin.sol";
import {Status, Statuses} from "./StatusLogic.sol";
import {Constants} from "./Constants.sol";

contract Vault is ERC721Enumerable, OperatorMixin, IVault {
    using SafeERC20 for IERC20;

    /// @notice Stuct using for vault configuration
    /// @notice `defii` - defii address
    /// @notice `weight` - defii weight
    /// @dev Weight should be in bps (eg 100% = 1e4)
    struct DefiiInfo {
        address defii;
        uint16 weight;
    }

    uint256 constant OPERATOR_POSITION_ID = 0;

    /// @notice Vault notion (start token for all DEFIIs)
    address public immutable NOTION;
    uint256 immutable NUM_DEFIIS;

    mapping(uint256 positionId => mapping(address token => uint256 balance))
        public positionBalance;
    mapping(uint256 positionId => Statuses statuses) _positionStatuses;

    mapping(uint256 positionId => uint256) _enterAmount;
    mapping(uint256 positionId => uint256) _exitPercentage;

    mapping(address defii => uint256 weight) public defiiWeight;
    mapping(address => uint256) _defiiIndex;
    address[] _defiis;

    modifier validateDefii(address defii) {
        _validateDefii(defii);
        _;
    }

    constructor(
        address operatorRegistry,
        DefiiInfo[] memory defiiConfig,
        string memory vaultName,
        string memory vaultSymbol
    ) ERC721(vaultName, vaultSymbol) OperatorMixin(operatorRegistry) {
        _safeMint(msg.sender, OPERATOR_POSITION_ID);

        NUM_DEFIIS = defiiConfig.length;
        NOTION = IDefii(defiiConfig[0].defii).notion();

        DefiiInfo memory defiiInfo;
        for (uint256 i = 0; i < NUM_DEFIIS; i++) {
            defiiInfo = defiiConfig[i];
            defiiWeight[defiiInfo.defii] = defiiInfo.weight;
            _defiiIndex[defiiInfo.defii] = i;
            _defiis.push(defiiInfo.defii);
        }
    }

    /// @inheritdoc IVault
    function depositWithPermit(
        address token,
        uint256 amount,
        uint256 operatorFeeAmount,
        uint256 deadline,
        uint8 permitV,
        bytes32 permitR,
        bytes32 permitS
    ) external returns (uint256 positionId) {
        IERC20Permit(token).permit({
            owner: msg.sender,
            spender: address(this),
            value: amount,
            deadline: deadline,
            v: permitV,
            r: permitR,
            s: permitS
        });
        positionId = _getPositionId(msg.sender, true);

        _deposit(positionId, token, amount, operatorFeeAmount);
    }

    /// @inheritdoc IVault
    function deposit(
        address token,
        uint256 amount,
        uint256 operatorFeeAmount
    ) external returns (uint256 positionId) {
        positionId = _getPositionId(msg.sender, true);

        _deposit(positionId, token, amount, operatorFeeAmount);
    }

    /// @inheritdoc IVault
    function depositToPosition(
        uint256 positionId,
        address token,
        uint256 amount,
        uint256 operatorFeeAmount
    ) external {
        if (operatorFeeAmount > amount) {
            // We can't pay more fees incase deposit to position,
            // because every one can deposit for any position
            operatorFeeAmount = amount;
        }
        _deposit(positionId, token, amount, operatorFeeAmount);
    }

    /// @notice Set exit percentage for caller position
    /// @param percentage How many shares to exit (in bps)
    /// @dev Can't call when position in processing
    function startExit(uint256 percentage) external {
        if (percentage > Constants.BPS) revert WrongExitPercentage(percentage);
        uint256 positionId = _getPositionId(msg.sender, false);
        _validatePositionNotProcessing(positionId);
        _exitPercentage[positionId] = percentage;
    }

    /// @inheritdoc IVault
    function withdraw(
        address token,
        uint256 amount,
        uint256 positionId
    ) external {
        if (token == NOTION) _validatePositionNotProcessing(positionId);

        address positionOwner = ownerOf(positionId);
        _operatorCheckApproval(positionOwner);
        _changeBalance(positionId, token, amount, false);
        IERC20(token).safeTransfer(positionOwner, amount);
    }

    /// @notice Burn DEFII lp and withdraw liquidity from DEFII to user wallet
    /// @param instructions Remote call instruction for remote defii, empty array for local defii
    function withdrawLiquidityFromDefii(
        uint256 positionId,
        address defii,
        IDefii.Instruction[] calldata instructions
    )
        external
        payable
        validateDefii(defii)
        operatorCheckApproval(ownerOf(positionId))
    {
        uint256 lpAmount = positionBalance[positionId][defii];
        _changeBalance(positionId, defii, lpAmount, false);

        IDefii(defii).withdrawLiquidity(msg.sender, lpAmount, instructions);
    }

    /// @inheritdoc IVault
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
        _changeDefiiStatus(positionId, defii, Status.ENTERING);

        uint256 amount = calculateEnterDefiiAmount(positionId, defii);
        _changeBalance(positionId, NOTION, amount, false);
        IERC20(NOTION).safeIncreaseAllowance(defii, amount);
        IDefii(defii).enter{value: msg.value}(amount, positionId, instructions);
    }

    /// @inheritdoc IVault
    function enterCallback(
        uint256 positionId,
        uint256 shares
    ) external validateDefii(msg.sender) {
        _changeBalance(positionId, msg.sender, shares, true);
        _changeDefiiStatus(positionId, msg.sender, Status.PROCESSED);
    }

    /// @inheritdoc IVault
    function exitDefii(
        address defii,
        uint256 positionId,
        IDefii.Instruction[] calldata instructions
    )
        external
        payable
        validateDefii(defii)
        operatorCheckApproval(ownerOf(positionId))
    {
        uint256 shares = calculateExitDefiiShares(positionId, defii);
        if (shares == 0) revert WrongExitPercentage(0);

        _changeDefiiStatus(positionId, defii, Status.EXITING);
        _changeBalance(positionId, defii, shares, false);
        IDefii(defii).exit{value: msg.value}(shares, positionId, instructions);
    }

    /// @inheritdoc IVault
    function exitCallback(
        uint256 positionId
    ) external validateDefii(msg.sender) {
        _changeDefiiStatus(positionId, msg.sender, Status.PROCESSED);

        if (!_isPositonProcessing(positionId)) {
            _exitPercentage[positionId] = 0;
        }
    }

    /// @notice Return vault DEFIIs
    /// @return Array with DEFIIs
    // solhint-disable-next-line named-return-values
    function getDefiis() external view returns (address[] memory) {
        return _defiis;
    }

    /// @notice Return position and defii statuses
    /// @param positionId Position id
    /// @return positionStatus position status
    /// @return defiiStatuses array with DEFII statuses
    function getPositionStatus(
        uint256 positionId
    )
        external
        view
        returns (Status positionStatus, Status[] memory defiiStatuses)
    {
        defiiStatuses = new Status[](_defiis.length);

        Statuses statuses = _positionStatuses[positionId];
        for (
            uint256 defiiIndex = 0;
            defiiIndex < _defiis.length;
            defiiIndex++
        ) {
            defiiStatuses[defiiIndex] = statuses.getDefiiStatus(defiiIndex);
        }

        return (statuses.getPositionStatus(), defiiStatuses);
    }

    /// @notice Calculate amount for enter for certain DEFII
    /// @param positionId Position id
    /// @param defii Defii address
    /// @return Enter amount for defii
    /// @dev Uses `defiiWeight` and `_enterAmount` vars
    // solhint-disable-next-line named-return-values
    function calculateEnterDefiiAmount(
        uint256 positionId,
        address defii
    ) public view returns (uint256) {
        return (_enterAmount[positionId] * defiiWeight[defii]) / Constants.BPS;
    }

    /// @notice Calculate amount of shares for exit for certain DEFII
    /// @param positionId Position id
    /// @param defii Defii address
    /// @return Exit shares amount for defii
    /// @dev Uses `positionBalance` and `_exitPercentage` vars
    // solhint-disable-next-line named-return-values
    function calculateExitDefiiShares(
        uint256 positionId,
        address defii
    ) public view returns (uint256) {
        return
            (_exitPercentage[positionId] * positionBalance[positionId][defii]) /
            Constants.BPS;
    }

    function _deposit(
        uint256 positionId,
        address token,
        uint256 amount,
        uint256 operatorFeeAmount
    ) internal {
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        _changeBalance(positionId, token, amount, true);
        if (operatorFeeAmount > 0) {
            _payOperatorFee(positionId, token, operatorFeeAmount);
        }

        if (token == NOTION && !_isDefii(msg.sender)) {
            _validatePositionNotProcessing(positionId);
            _enterAmount[positionId] = positionBalance[positionId][NOTION];
        }
    }

    function _getPositionId(
        address user,
        bool mint
    ) internal returns (uint256 positionId) {
        if (balanceOf(user) == 0 && mint) {
            positionId = totalSupply();
            _safeMint(user, positionId);
        } else {
            positionId = tokenOfOwnerByIndex(user, 0);
        }
    }

    function _changeBalance(
        uint256 positionId,
        address token,
        uint256 amount,
        bool increase
    ) internal {
        if (amount == 0) return;

        if (increase) {
            positionBalance[positionId][token] += amount;
        } else {
            uint256 balance = positionBalance[positionId][token];
            if (balance < amount) {
                revert InsufficientBalance(positionId, token, balance, amount);
            }
            unchecked {
                positionBalance[positionId][token] = balance - amount;
            }
        }

        emit BalanceChanged(positionId, token, amount, increase);
    }

    function _changeDefiiStatus(
        uint256 positionId,
        address defii,
        Status newStatus
    ) internal {
        uint256 defiiIndex = _defiiIndex[defii];

        _positionStatuses[positionId] = Statuses(_positionStatuses[positionId])
            .updateDefiiStatus(defiiIndex, newStatus, NUM_DEFIIS);
        emit DefiiStatusChanged(positionId, defii, newStatus);
    }

    function _payOperatorFee(
        uint256 positionId,
        address token,
        uint256 operatorFeeAmount
    ) internal {
        _changeBalance(positionId, token, operatorFeeAmount, false);
        _changeBalance(OPERATOR_POSITION_ID, token, operatorFeeAmount, true);
    }

    function _validateDefii(address defii) internal view {
        if (!_isDefii(defii)) {
            revert UnsupportedDefii(defii);
        }
    }

    // solhint-disable-next-line named-return-values
    function _isDefii(address defii) internal view returns (bool) {
        return defiiWeight[defii] > 0;
    }

    function _validatePositionNotProcessing(uint256 positionId) internal view {
        if (_isPositonProcessing(positionId)) {
            revert PositionProcessing();
        }
    }

    // solhint-disable-next-line named-return-values
    function _isPositonProcessing(
        uint256 positionId
    ) internal view returns (bool) {
        return
            Statuses(_positionStatuses[positionId]).getPositionStatus() !=
            Status.NOT_PROCESSING;
    }
}

