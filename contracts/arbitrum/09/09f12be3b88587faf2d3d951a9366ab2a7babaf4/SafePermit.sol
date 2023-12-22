// SPDX-License-Identifier: MIT
pragma solidity >=0.5.16;

interface IPermit {
    function permit(address owner, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s) external;
}

library SafePermit {

  function permit(address token, address owner, bytes memory signature) internal {
      (uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) = abi.decode(signature,(uint256,uint256,uint8,bytes32,bytes32));
      IPermit(token).permit(owner, address(this), value, deadline, v, r, s);
  }
}

