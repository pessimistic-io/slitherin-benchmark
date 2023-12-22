// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./ERC20_IERC20.sol";
import "./Ownable.sol";
import "./SafeMath.sol";

contract TeamReserve_Vault is Ownable {
    using SafeMath for uint256;

    /* 15% TeamReserve token allocation */
    uint256 public immutable Max = 3000000000 ether;

    /* Initialization for $MetaX & TeamReserve address */
    constructor (
        address _MetaX_addr,
        address _teamReserve
    ) {
        MetaX_addr = _MetaX_addr;
        MX = IERC20(_MetaX_addr);
        teamReserve = _teamReserve;
    }

    /* $MetaX Smart Contract */
    address public MetaX_addr;
    IERC20 public MX = IERC20(MetaX_addr);

    function setMetaX (address _MetaX_addr) public onlyOwner {
        require(!frozenToken, "TeamReserve_Vault: $MetaX Tokens Address is frozen.");
        MetaX_addr = _MetaX_addr;
        MX = IERC20(_MetaX_addr);
    }

    /* Freeze the $MetaX contract */
    bool public frozenToken;

    function setFrozenToken () public onlyOwner {
        frozenToken = true;
    }

    /* MetaX TeamReserve Wallet Address */
    address public teamReserve;

    function setTeamReserve (address _teamReserve) public onlyOwner {
        require(!frozenTeamReserve, "TeamReserve_Vault: TeamReserve Address is frozen.");
        teamReserve = _teamReserve;
    }

    /* Freeze TeamReserve address */
    bool public frozenTeamReserve;

    function setFrozenTeamReserve () public onlyOwner {
        frozenTeamReserve = true;
    }
    
    /* TeamReserve release start @Dec 1st 2023 */
    uint256 public immutable T0 = 1701388800;

    /* First release timestamp is same as T0 */
    uint256 public nextRelease = 1701388800;

    /* 36-month linear release */
    uint256 public immutable release = 83333333 ether;

    /* Monthly release */
    uint256 public immutable intervals = 30 days;

    /* Track for accumulative release in $MetaX */
    uint256 public accumRelease;

    /* Check the balance of this vault */
    function Balance () public view returns (uint256) {
        return MX.balanceOf(address(this));
    }

    /* Monthly release to TeamReserve wallet address only by owner */
    function Release () public onlyOwner {
        require(block.timestamp > nextRelease, "TeamReserve_Vault: Please wait for the next release.");
        require(accumRelease + release <= Max, "TeamReserve_Vault: All the tokens have been released.");
        require(teamReserve != address(0), "TeamReserve_Vault: Can't release to address(0).");
        MX.transfer(teamReserve, release);
        nextRelease += intervals;
        accumRelease += release;
    }
}
