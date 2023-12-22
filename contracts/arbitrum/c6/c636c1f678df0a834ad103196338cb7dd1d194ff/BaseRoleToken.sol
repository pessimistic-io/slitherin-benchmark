// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;
import "./ERC20.sol";
import "./AccessControlDefaultAdminRules.sol";
import "./draft-ERC20Permit.sol";
import { IErrors } from "./Interfaces.sol";

interface IBaseRoleToken {
  function inPrivateTransferMode() external view returns (bool);
}

contract BaseRoleToken is IBaseRoleToken, IErrors, ERC20, ERC20Permit, AccessControlDefaultAdminRules {
  bytes32 public constant UNSAFE_TRANSFER_IN = keccak256('UNSAFE_TRANSFER_IN'); // note: bypass approvals
  bytes32 public constant TRANSFER_OUT = keccak256('TRANSFER_OUT');
  bytes32 public constant TRANSFER_IN = keccak256('TRANSFER_IN');

  bool public inPrivateTransferMode;

  constructor(
    string memory _name,
    string memory _symbol,
    bool _isTransferPermissioned
  ) ERC20(_name, _symbol) ERC20Permit(_name) AccessControlDefaultAdminRules(0, msg.sender) {
    inPrivateTransferMode = _isTransferPermissioned;
  }

  function transferFrom(address from, address to, uint256 amount) public virtual override returns (bool) {
    if (hasRole(UNSAFE_TRANSFER_IN, _msgSender()) == false) {
      address spender = _msgSender();
      _spendAllowance(from, spender, amount);
    }

    _transfer(from, to, amount);
    return true;
  }

  function _transfer(address from, address to, uint amount) internal override {
    if (from == to) revert FAILED((string.concat(symbol(), ': ', 'from == to')));
    _validateTransferRoles(from, to);
    super._transfer(from, to, amount);
  }

  function setInPrivateTransferMode(bool _inPrivateTransferMode) external onlyOwner {
    inPrivateTransferMode = _inPrivateTransferMode;
  }

  function recoverErc20(IERC20 _erc20, uint _amount) external onlyOwner {
    IERC20(_erc20).transfer(owner(), _amount);
  }

  modifier onlyOwner() {
    _checkRole(DEFAULT_ADMIN_ROLE);
    _;
  }

  function _validateTransferRoles(address from, address to) private view {
    bool canUnsafeTransferIn = hasRole(UNSAFE_TRANSFER_IN, _msgSender()) && to == _msgSender();
    bool canTransferIn = hasRole(TRANSFER_IN, _msgSender()) && to == _msgSender();
    bool canTransferOut = hasRole(TRANSFER_OUT, _msgSender()) && from == _msgSender();

    if (canUnsafeTransferIn) return;
    if (canTransferIn) return;
    if (canTransferOut) return;
    if (!inPrivateTransferMode) return;

    revert UNAUTHORIZED(string.concat(symbol(), ': ', '!transfer'));
  }
}

