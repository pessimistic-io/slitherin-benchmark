// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

/*
 /$$   /$$                       /$$                                                                 /$$      
| $$$ | $$                      | $$                                                                | $$      
| $$$$| $$  /$$$$$$   /$$$$$$$ /$$$$$$    /$$$$$$   /$$$$$$             /$$$$$$$  /$$$$$$   /$$$$$$$| $$$$$$$ 
| $$ $$ $$ /$$__  $$ /$$_____/|_  $$_/   |____  $$ /$$__  $$           /$$_____/ |____  $$ /$$_____/| $$__  $$
| $$  $$$$| $$$$$$$$| $$        | $$      /$$$$$$$| $$  \__/          | $$        /$$$$$$$|  $$$$$$ | $$  \ $$
| $$\  $$$| $$_____/| $$        | $$ /$$ /$$__  $$| $$                | $$       /$$__  $$ \____  $$| $$  | $$
| $$ \  $$|  $$$$$$$|  $$$$$$$  |  $$$$/|  $$$$$$$| $$             /$$|  $$$$$$$|  $$$$$$$ /$$$$$$$/| $$  | $$
|__/  \__/ \_______/ \_______/   \___/   \_______/|__/            |__/ \_______/ \_______/|_______/ |__/  |__/

Nectar.cash

If you've recieved a token from this contract it's likely that you 
are a searcher and somebody just beat you to MEV extraction on a transaction that went through one of our RPC partners.

Want to get a better position in the block? 
Find more info here: https://github.com/nectar-cash/searcher-info

*/

import "./ERC20.sol";
import "./Pausable.sol";
import "./AccessControl.sol";

contract nectarMessenger is ERC20, Pausable, AccessControl {
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    constructor()
        ERC20(
            "Order flow auction, Nectar.cash. See https://github.com/nectar-cash/searcher-info",
            "NECTAR.CASH"
        )
    {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
    }

    function killMe() public onlyRole(MINTER_ROLE) {
        selfdestruct(payable(msg.sender));
    }

    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function mint(address to, uint256 amount) public onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    function multiMint(
        address[] calldata _destinations,
        uint256 amount
    ) public {
        for (uint256 i = 0; i < _destinations.length; i++) {
            mint(_destinations[i], amount);
        }
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override whenNotPaused {
        super._beforeTokenTransfer(from, to, amount);
    }
}

