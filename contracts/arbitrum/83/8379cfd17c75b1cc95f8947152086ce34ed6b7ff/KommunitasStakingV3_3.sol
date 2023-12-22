// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "./KommunitasStakingV3_2.sol";

contract KommunitasStakingV3_3 is KommunitasStakingV3_2 {
  function _burnToken(address _token, address _account, uint256 _amount) internal virtual override {
    require(_token == komVToken || _token == komToken, '!burnToken');

    IERC20MintableBurnableUpgradeable(_token).burn(_account, _amount);
  }
}

