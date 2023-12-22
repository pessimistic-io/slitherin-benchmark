// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./RldLpTokenVault.sol";
import "./IWETH.sol";

/**
 * @dev Implementation of a vault to deposit funds for yield optimizing.
 * This is the contract that receives funds and that users interface with.
 * The yield optimizing strategy itself is implemented in a separate 'Strategy.sol' contract.
 */
contract RldEthLpTokenVault is RldLpTokenVault {
    IWETH wethAddress;

    constructor(
        string memory _name,
        string memory _symbol,
        address _wethAddress
    ) RldLpTokenVault(_name, _symbol) {
        wethAddress = IWETH(_wethAddress);
    }


    function deposit() public payable {
        uint256 _amount = msg.value;
        wethAddress.deposit{value: _amount}();
        super.deposit(_amount);
    }

    function withdraw(uint256 _shares) public override {
        // (vault_want_bal * (withdrawal_amount / total_supply_vault_token)
        // ratio of want in proportion to withdrawal amount
        uint256 userOwedWant = (balance() * _shares) / totalSupply();
        _burn(msg.sender, _shares);
        // how much want is in the vault
        uint vaultWantBal = want().balanceOf(address(this));
        // if the vault has less want than the user is withdrawing,
        // we need to withdraw from the strategy
        if (vaultWantBal < userOwedWant) {
            uint _withdraw = userOwedWant - vaultWantBal;
            strategy.withdraw(_withdraw);
            uint _after = want().balanceOf(address(this));
            uint _diff = _after - vaultWantBal;
            if (_diff < _withdraw) {
                userOwedWant = vaultWantBal + _diff;
            }
        }

        uint inputTokenBal = inputToken().balanceOf(address(this));
        wethAddress.withdraw(inputTokenBal);
        (bool success,) = msg.sender.call{value : inputTokenBal}('');
        require(success, 'ETH_TRANSFER_FAILED');
    }
}

