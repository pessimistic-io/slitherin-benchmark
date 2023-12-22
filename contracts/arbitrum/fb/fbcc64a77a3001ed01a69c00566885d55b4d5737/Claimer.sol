// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./SafeERC20.sol";

interface Strategy {
     function claim(
        address[] calldata _tokens,
        uint256[] calldata _amounts,
        bytes32[][] calldata _proofs
    ) external;
}
contract Claimer {
    using SafeERC20 for IERC20;

    IERC20 public constant token = IERC20(0xd4d42F0b6DEF4CE0383636770eF773390d85c61A);

    function claim(address _strategy, address[] calldata _tokens, uint256[] calldata _amounts, bytes32[][] calldata _proofs) external returns (uint256 amount) {
        uint256 before = token.balanceOf(_strategy);
        Strategy(_strategy).claim(_tokens, _amounts, _proofs);
        amount = token.balanceOf(_strategy) - before;
    }

}
