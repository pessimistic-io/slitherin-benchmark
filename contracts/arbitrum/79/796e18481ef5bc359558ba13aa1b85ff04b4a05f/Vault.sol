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

contract Vault is ERC721Enumerable, OperatorMixin, IVault {
    using SafeERC20 for IERC20;

    struct DefiiInfo {
        address defii;
        uint16 weight; // bps
    }

    address[] _defiis;
    mapping(uint256 positionId => mapping(address token => uint256 balance))
        public funds;
    mapping(address => uint256) public defiiWeight;

    constructor(
        DefiiInfo[] memory defiiConfig,
        string memory vaultName,
        string memory vaultSymbol
    ) ERC721(vaultName, vaultSymbol) {
        DefiiInfo memory defiiInfo;
        for (uint256 i = 0; i < defiiConfig.length; i++) {
            defiiInfo = defiiConfig[i];

            defiiWeight[defiiInfo.defii] = defiiInfo.weight;
            _defiis.push(defiiInfo.defii);
        }
    }

    function depositWithPermit(
        address token,
        uint256 amount,
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
        deposit(token, amount);
    }

    function deposit(address token, uint256 amount) public {
        uint256 positionId = _getPositionId(msg.sender, true);

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        funds[positionId][token] += amount;
        emit FundsDeposited(token, positionId, amount);
    }

    function withdraw(
        address token,
        uint256 amount,
        uint256 positionId
    ) external {
        address tokenOwner = ownerOf(positionId);
        _operatorCheckApproval(tokenOwner);

        funds[positionId][token] -= amount;
        IERC20(token).safeTransfer(tokenOwner, amount);
        emit FundsWithdrawn(token, positionId, amount);
    }

    function enterDefii(
        address defii,
        uint256 positionId,
        uint256 amount,
        IDefii.Instruction[] calldata instructions
    ) external payable {
        address positionOwner = ownerOf(positionId);
        _operatorCheckApproval(positionOwner);
        _checkDefii(defii);

        address notion = IDefii(defii).notion();
        funds[positionId][notion] -= amount;
        IERC20(notion).safeIncreaseAllowance(defii, amount);
        IDefii(defii).enter{value: msg.value}(
            amount,
            positionOwner,
            instructions
        );
    }

    function exitDefii(
        address defii,
        uint256 positionId,
        uint256 percentage, // bps
        IDefii.Instruction[] calldata instructions
    ) external payable {
        address positionOwner = ownerOf(positionId);
        _operatorCheckApproval(positionOwner);
        _checkDefii(defii);

        uint256 lpAmount = (funds[positionId][defii] * percentage) / 1e4;

        funds[positionId][defii] -= lpAmount;
        IDefii(defii).exit{value: msg.value}(
            lpAmount,
            positionOwner,
            instructions
        );
    }

    function requestForExit(
        uint256 percentage // bps
    ) external {
        _requestForAction(abi.encodeWithSignature("exit(uint256)", percentage));
    }

    function collectFunds(
        address,
        address to,
        address token,
        uint256 amount
    ) external {
        uint256 positionId = _getPositionId(to, true);

        funds[positionId][token] += amount;
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        emit FundsCollected(token, positionId, amount);
    }

    function getDefiis() external view returns (address[] memory) {
        return _defiis;
    }

    function _checkDefii(address defii) internal view {
        if (defiiWeight[defii] == 0) {
            revert UnsupportedDefii(defii);
        }
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
}

