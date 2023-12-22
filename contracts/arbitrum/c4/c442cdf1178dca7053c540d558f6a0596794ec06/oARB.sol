pragma solidity 0.8.17;

import { ERC20 } from "./tokens_ERC20.sol";
import { GlobalACL, Auth, CONTROLLER } from "./Auth.sol";

/**
 * @title   OARB
 * @author  UmamiDAO
 *
 * ERC20 contract for oARB tokens
 */
contract OARB is ERC20, GlobalACL {
    // ==================================================================
    // ======================= Constructor =======================
    // ==================================================================

    constructor(Auth _auth) ERC20("oARB Token", "oARB", 18) GlobalACL(_auth) { }

    // ==================================================================
    // ======================= External Functions =======================
    // ==================================================================

    // @follow-up Do we want to add address parameter?
    function mint(address account, uint256 _amount) external onlyController {
        _mint(account, _amount);
    }

    function burn(uint256 _amount) external onlyController {
        _burn(msg.sender, _amount);
    }
}

