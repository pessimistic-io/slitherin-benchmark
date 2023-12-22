// SPDX-License-Identifier: MIT
import {ERC20} from "./ERC20.sol";
import {AccessControl} from "./AccessControl.sol";
pragma solidity 0.8.17;

contract GNSDaiTokenV5 is ERC20, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    constructor() ERC20("GNS TEST DAI", "GNSTESTDAI") {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(MINTER_ROLE, msg.sender);
    }

    function mint(address to, uint amount) external {
        require(hasRole(MINTER_ROLE, msg.sender), "Caller is not a minter");
        _mint(to, amount);
    }

    // Get 1000 free DAI
    function getFreeDai() external{
        _mint(msg.sender, 10000*1e18);
    }
}


