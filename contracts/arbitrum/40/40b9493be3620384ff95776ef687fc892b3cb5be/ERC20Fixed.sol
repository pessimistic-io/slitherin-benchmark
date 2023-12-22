// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

import "./FixedPoint.sol";
import "./ERC20.sol";
import "./SafeERC20.sol";
import "./ERC20Burnable.sol";
import "./ERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./ERC20BurnableUpgradeable.sol";

library ERC20Fixed {
  using FixedPoint for uint256;
  // audit(B): M03
  using SafeERC20 for ERC20;
  using SafeERC20Upgradeable for ERC20Upgradeable;

  function transferFixed(ERC20 _token, address _to, uint256 _amount) internal {
    if (_amount > 0)
      _token.safeTransfer(_to, _amount / (10 ** (18 - _token.decimals())));
  }

  function transferFromFixed(
    ERC20 _token,
    address _from,
    address _to,
    uint256 _amount
  ) internal {
    if (_amount > 0)
      _token.safeTransferFrom(
        _from,
        _to,
        _amount / (10 ** (18 - _token.decimals()))
      );
  }

  function balanceOfFixed(
    ERC20 _token,
    address _owner
  ) internal view returns (uint256) {
    return _token.balanceOf(_owner) * (10 ** (18 - _token.decimals()));
  }

  function totalSupplyFixed(ERC20 _token) internal view returns (uint256) {
    return _token.totalSupply() * (10 ** (18 - _token.decimals()));
  }

  function allowanceFixed(
    ERC20 _token,
    address _owner,
    address _spender
  ) internal view returns (uint256) {
    return
      _token.allowance(_owner, _spender) * (10 ** (18 - _token.decimals()));
  }

  function approveFixed(
    ERC20 _token,
    address _spender,
    uint256 _amount
  ) internal returns (bool) {
    _token.safeApprove(_spender, _amount / (10 ** (18 - _token.decimals())));
    return true;
  }

  function increaseAllowanceFixed(
    ERC20 _token,
    address _spender,
    uint256 _addedValue
  ) internal returns (bool) {
    _token.safeIncreaseAllowance(
      _spender,
      _addedValue / (10 ** (18 - _token.decimals()))
    );
    return true;
  }

  function decreaseAllowanceFixed(
    ERC20 _token,
    address _spender,
    uint256 _subtractedValue
  ) internal returns (bool) {
    _token.safeDecreaseAllowance(
      _spender,
      _subtractedValue / (10 ** (18 - _token.decimals()))
    );
    return true;
  }

  function transferFixed(
    ERC20Upgradeable _token,
    address _to,
    uint256 _amount
  ) internal {
    if (_amount > 0)
      _token.safeTransfer(_to, _amount / (10 ** (18 - _token.decimals())));
  }

  function transferFromFixed(
    ERC20Upgradeable _token,
    address _from,
    address _to,
    uint256 _amount
  ) internal {
    if (_amount > 0)
      _token.safeTransferFrom(
        _from,
        _to,
        _amount / (10 ** (18 - _token.decimals()))
      );
  }

  function balanceOfFixed(
    ERC20Upgradeable _token,
    address _owner
  ) internal view returns (uint256) {
    return _token.balanceOf(_owner) * (10 ** (18 - _token.decimals()));
  }

  function totalSupplyFixed(
    ERC20Upgradeable _token
  ) internal view returns (uint256) {
    return _token.totalSupply() * (10 ** (18 - _token.decimals()));
  }

  function allowanceFixed(
    ERC20Upgradeable _token,
    address _owner,
    address _spender
  ) internal view returns (uint256) {
    return
      _token.allowance(_owner, _spender) * (10 ** (18 - _token.decimals()));
  }

  function approveFixed(
    ERC20Upgradeable _token,
    address _spender,
    uint256 _amount
  ) internal returns (bool) {
    _token.safeApprove(_spender, _amount / (10 ** (18 - _token.decimals())));
    return true;
  }

  function increaseAllowanceFixed(
    ERC20Upgradeable _token,
    address _spender,
    uint256 _addedValue
  ) internal returns (bool) {
    _token.safeIncreaseAllowance(
      _spender,
      _addedValue / (10 ** (18 - _token.decimals()))
    );
    return true;
  }

  function decreaseAllowanceFixed(
    ERC20Upgradeable _token,
    address _spender,
    uint256 _subtractedValue
  ) internal returns (bool) {
    _token.safeDecreaseAllowance(
      _spender,
      _subtractedValue / (10 ** (18 - _token.decimals()))
    );
    return true;
  }

  function burnFixed(ERC20Burnable _token, uint256 _amount) internal {
    _token.burn(_amount / (10 ** (18 - _token.decimals())));
  }

  function burnFromFixed(
    ERC20Burnable _token,
    address _from,
    uint256 _amount
  ) internal {
    _token.burnFrom(_from, _amount / (10 ** (18 - _token.decimals())));
  }

  function burnFixed(
    ERC20BurnableUpgradeable _token,
    uint256 _amount
  ) internal {
    _token.burn(_amount / (10 ** (18 - _token.decimals())));
  }

  function burnFromFixed(
    ERC20BurnableUpgradeable _token,
    address _from,
    uint256 _amount
  ) internal {
    _token.burnFrom(_from, _amount / (10 ** (18 - _token.decimals())));
  }
}

