// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./ERC20_IERC20.sol";
import "./AccessControl.sol";
import "./Ownable.sol";
import "./SafeMath.sol";

contract BuilderIncentives_Vault is AccessControl, Ownable {
    using SafeMath for uint256;

    /* 5% BuilderIncentives token allocation */
    uint256 public immutable Max = 1000000000 ether;

    /* Admin role for daily linear release */
    bytes32 public constant Admin = keccak256("Admin");

    /* Initialization for $MetaX & nextRelease timestamp & Admins */
    constructor(
        address _MetaX_addr,
        uint256 _nextRelease
    ) {
        MetaX_addr = _MetaX_addr;
        MX = IERC20(_MetaX_addr);
        nextRelease = _nextRelease;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(Admin, msg.sender);
    }

    /* $MetaX Smart Contract */
    address public MetaX_addr;
    IERC20 public MX = IERC20(MetaX_addr);

    function setMetaX (address _MetaX_addr) public onlyOwner {
        require(!frozenToken, "BuilderIncentives_Vault: $MetaX Tokens Address is frozen.");
        MetaX_addr = _MetaX_addr;
        MX = IERC20(_MetaX_addr);
    }

    /* Freeze the $MetaX contract */
    bool public frozenToken;

    function setFrozenToken () public onlyOwner {
        frozenToken = true;
    }

    /* BuilderIncentives Smart Contract */
    address public BuilderIncentives_addr;

    function setBuilderIncentives (address newBuilderIncentives_addr) public onlyOwner {
        require(!frozenBuilderIncentives, "BuilderIncentives_Vault: BuilderIncentives Address is frozen.");
        BuilderIncentives_addr = newBuilderIncentives_addr;
    }

    /* Freeze the BuilderIncentives contract */
    bool public frozenBuilderIncentives;

    function setFrozenBuilderIncentives () public onlyOwner {
        frozenBuilderIncentives = true;
    }

    /* BuilderIncentives start @Feb 14th 2023 */
    uint256 public T0 = 1676332800;

    /* Daily release quota */
    uint256 public release = 684931 ether;

    /* Daily linear release mechanism */
    uint256 public immutable intervals = 1 days;

    /* Track for next release timestamp */
    uint256 public nextRelease;

    /* Track for accumulative release for $MetaX */
    uint256 public accumRelease;

    /* Halving every 2 years */
    function Halve () public onlyOwner {
        require(block.timestamp > T0 + 730 days, "BuilderIncentives_Vault: Please wait till the next halving.");
        release = release.div(2);
        T0 += 730 days;
    }

    /* Check the balance of this vault */
    function Balance () public view returns (uint256) {
        return MX.balanceOf(address(this));
    }

    /* Daily release to BuilderIncentives only by Admins */
    function Release () public onlyRole(Admin) {
        require(block.timestamp > nextRelease, "BuilderIncentives_Vault: Please wait for the next release.");
        require(BuilderIncentives_addr != address(0), "BuilderIncentives_Vault: Can't release to address(0).");
        MX.transfer(BuilderIncentives_addr, release);
        accumRelease += release;
        nextRelease += intervals;
    }
}
