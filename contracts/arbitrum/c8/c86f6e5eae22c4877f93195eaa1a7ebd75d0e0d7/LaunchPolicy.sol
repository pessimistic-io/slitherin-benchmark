pragma solidity ^0.8.0;

import { SafeTransferLib, ERC20 } from "./SafeTransferLib.sol";

import "./Kernel.sol";

// module dependancies
import { GMBL } from "./GMBL.sol";
import { RGMBL } from "./RGMBL.sol";
import { ROLES } from "./ROLES.sol";

contract LaunchPolicy is Policy {

    GMBL  public gmbl;
    RGMBL public rgmbl;
    ROLES public roles;

    constructor(Kernel kernel_) Policy(kernel_) {}

    function configureDependencies() external override onlyKernel returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](3);
        dependencies[0] = toKeycode("GMBLE");
        dependencies[1] = toKeycode("RGMBL");
        dependencies[2] = toKeycode("ROLES");

        gmbl = GMBL(getModuleAddress(dependencies[0]));
        rgmbl = RGMBL(getModuleAddress(dependencies[1]));
        roles = ROLES(getModuleAddress(dependencies[2]));
    }

    function requestPermissions()
        external
        pure
        override
        returns (Permissions[] memory requests)
    {
        requests = new Permissions[](2);
        requests[0] = Permissions(toKeycode("GMBLE"), GMBL.mint.selector);
        requests[1] = Permissions(toKeycode("RGMBL"), RGMBL.mint.selector);
    }

    /// @notice Role-gated function to mint GMBL (up to maxSupply)
    /// @param amount Amount to mint to msg.sender
    function mint(uint256 amount) external {
        roles.requireRole("minter", msg.sender);
        gmbl.mint(msg.sender, amount);
    }

    /// @notice Role-gated function to mint rGMBL (up to maxSupply)
    /// @param amount Amount to mint to msg.sender
    function mintReceiptToken(uint256 amount) external {
        roles.requireRole("minter", msg.sender);
        rgmbl.mint(msg.sender, amount);
    }
}
