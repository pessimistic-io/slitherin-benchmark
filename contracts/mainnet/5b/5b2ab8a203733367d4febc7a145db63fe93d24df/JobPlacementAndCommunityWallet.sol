// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "./console.sol";
import "./IERC20.sol";
import "./SafeMath.sol";

contract JobPlacementAndCommunityWallet {
    IERC20 public token;
    uint today;

    constructor(address erc20_contract) {
        token = IERC20(erc20_contract);
        today = 0;
    }

    function balancing_menegment() payable public {
        require (block.timestamp >= today + 30.42 days, "you are trying to run a procedure before the time expires");

        address dead_wallet = 0x000000000000000000000000000000000000dEaD;
        address salary_wallet = 0x93bCC3981ce0eE99a4a0fdC3a8bdAe146ea2B9A7;

        (bool div_tokens_to_burn_success, uint256 tokens_to_burn) = SafeMath.tryDiv(token.balanceOf(address(this)), 40);
        require(div_tokens_to_burn_success, "Dividing tokens_to_burn failed.");

        (bool div_tokens_buff_success, uint256 tokens_buff) = SafeMath.tryDiv(token.balanceOf(address(this)), 20);
        require(div_tokens_buff_success, "Dividing tokens_buff failed.");

        (bool mul_mathematical_operation_buff_success, uint256 mathematical_operation_buff) = SafeMath.tryMul(tokens_buff, 19);
        require(mul_mathematical_operation_buff_success, "Multiplication mathematical_operation_buff failed.");

        (bool div_tokens_to_send_success, uint256 tokens_to_send) = SafeMath.tryDiv(mathematical_operation_buff, 100);
        require(div_tokens_to_send_success, "Dividing tokens_to_send failed.");

        today = block.timestamp;

        token.transfer(dead_wallet, tokens_to_burn);
        token.transfer(salary_wallet, tokens_to_send);
    }
}
