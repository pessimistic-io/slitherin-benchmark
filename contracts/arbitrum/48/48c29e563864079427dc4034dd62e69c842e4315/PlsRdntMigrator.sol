// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.20;

import "./Pausable.sol";
import "./Ownable2Step.sol";
import "./IERC20.sol";
import "./IERC4626.sol";

import { ITokenMinter, IErrors } from "./Common.sol";
import { IRateProvider } from "./v2_Interfaces.sol";
import { IInvariant } from "./Invariant.sol";

interface IPlsRdntMigrator is IErrors {
  function migrate() external;

  function migrate(uint _amount) external;

  function migrateOnBehalf(address _user) external returns (uint _bal);

  event Migrated(address indexed _user, uint _amount, uint _shares);
}

contract PlsRdntMigrator is IPlsRdntMigrator, Ownable2Step, Pausable {
  address public immutable PLSRDNT;
  address public immutable PLSRDNTV2;
  address public immutable VDLP;
  IInvariant public invariant;

  mapping(address => bool) private handlers;

  constructor(address _plsrdnt, address _plsrdntv2, address _vdlp, IInvariant _invariant) Ownable(msg.sender) {
    PLSRDNT = _plsrdnt;
    PLSRDNTV2 = _plsrdntv2;
    VDLP = _vdlp;
    invariant = _invariant;

    IERC20(VDLP).approve(PLSRDNTV2, type(uint).max);
    _pause();
  }

  function migrate() external {
    uint bal = IERC20(PLSRDNT).balanceOf(msg.sender);
    _migrate(msg.sender, bal);
  }

  function migrate(uint _amount) external {
    _migrate(msg.sender, _amount);
  }

  function migrateOnBehalf(address _user) external returns (uint _bal) {
    if (handlers[msg.sender] == false) revert UNAUTHORIZED();

    _bal = IERC20(PLSRDNT).balanceOf(_user);
    _migrate(_user, _bal);
  }

  function _migrate(address _user, uint _amount) private whenNotPaused {
    ITokenMinter(PLSRDNT).burn(_user, _amount);
    ITokenMinter(VDLP).mint(address(this), _amount);
    uint shares = IERC4626(PLSRDNTV2).deposit(_amount, _user);

    emit Migrated(_user, _amount, shares);

    if (address(invariant) != address(0)) {
      invariant.checkHold();
    }
  }

  function setPause(bool _isPaused) external onlyOwner {
    if (_isPaused) {
      _pause();
    } else {
      _unpause();
    }
  }

  function setInvariant(IInvariant _newInvariant) external onlyOwner {
    invariant = _newInvariant;
  }

  function updateHandler(address _handler, bool _isActive) external onlyOwner {
    handlers[_handler] = _isActive;
  }
}

