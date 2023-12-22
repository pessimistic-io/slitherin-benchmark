// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;
import "./BaseRoleToken.sol";

interface IBaseRoleMintableToken {
  function mint(address _account, uint _amount) external;

  function burn(address _account, uint _amount) external;
}

contract BaseRoleMintableToken is IBaseRoleMintableToken, BaseRoleToken {
  bytes32 public constant MINTER = keccak256('MINTER');
  bytes32 public constant BURNER = keccak256('BURNER');

  constructor(
    string memory _name,
    string memory _symbol,
    bool _isTransferPermissioned
  ) BaseRoleToken(_name, _symbol, _isTransferPermissioned) {}

  function mint(address _account, uint _amount) external onlyRole(MINTER) {
    _mint(_account, _amount);
  }

  function burn(address _account, uint _amount) external onlyRole(BURNER) {
    _burn(_account, _amount);
  }
}

