// SPDX-License-Identifier: AGPL-3.0
pragma solidity =0.8.7;

import "./IBlocklistTransferHook.sol";
import "./IAccountList.sol";
import "./SafeOwnable.sol";

contract BlocklistTransferHook is IBlocklistTransferHook, SafeOwnable {
  IAccountList private _blocklist;

  constructor() {}

  function hook(
    address _from,
    address _to,
    uint256 _amount
  ) public virtual override {
    IAccountList _list = _blocklist;
    require(!_list.isIncluded(_from), "Sender blocked");
    require(!_list.isIncluded(_to), "Recipient blocked");
  }

  function setBlocklist(IAccountList _newBlocklist)
    external
    override
    onlyOwner
  {
    _blocklist = _newBlocklist;
    emit BlocklistChange(_newBlocklist);
  }

  function getBlocklist() external view override returns (IAccountList) {
    return _blocklist;
  }
}

