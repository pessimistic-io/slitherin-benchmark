// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import {ERC20} from "./ERC20.sol";
import {StakedBarnBridgeToken} from "./XBOND.sol";
import "./Kernel.sol";

error BarnStakingPolicy_NotVested();
error BarnStakingPolicy_NotWarmedUp();

/// @notice Policy to mint and burn XBOND to arbitrary addresses
contract BarnStakingPolicy is Policy {
    StakedBarnBridgeToken public XBOND;
    ERC20 public bond;

    /*//////////////////////////////////////////////////////////////
                            POLICY INTERFACE
    //////////////////////////////////////////////////////////////*/

    constructor(Kernel _kernel, ERC20 _bond) Policy(_kernel) {
        bond = _bond;
    }

    /// @inheritdoc Policy
    function configureDependencies() external override returns (bytes5[] memory dependencies) {
        dependencies = new bytes5[](1);
        dependencies[0] = bytes5("XBOND");

        XBOND = StakedBarnBridgeToken(getModuleAddress(dependencies[0]));
        bond.approve(address(XBOND), type(uint256).max);
    }

    /// @inheritdoc Policy
    function requestPermissions()
        external
        view
        override
        returns (Permissions[] memory permissions)
    {
        permissions = new Permissions[](6);
        permissions[0] = Permissions("XBOND", XBOND.deposit.selector);
        permissions[1] = Permissions("XBOND", XBOND.mint.selector);
        permissions[2] = Permissions("XBOND", XBOND.withdraw.selector);
        permissions[3] = Permissions("XBOND", XBOND.redeem.selector);
        permissions[4] = Permissions("XBOND", XBOND.resetActionTimestamp.selector);
        permissions[5] = Permissions("XBOND", XBOND.transferFrom.selector);

    }

    /*//////////////////////////////////////////////////////////////
                               CORE LOGIC
    //////////////////////////////////////////////////////////////*/

    uint256 public constant VESTING_PERIOD = 1 weeks;

    modifier onlyVested() {
        if (block.timestamp < XBOND.lastActionTimestamp(msg.sender) + VESTING_PERIOD) {
            revert BarnStakingPolicy_NotVested();
        }
        _;
    }

    function deposit(uint256 _assets) public {
        bond.transferFrom(msg.sender, address(this), _assets);
        XBOND.deposit(_assets, msg.sender);
    }

    function mint(uint256 _shares) public {
        uint256 assets = XBOND.previewMint(_shares);
        bond.transferFrom(msg.sender, address(this), assets);
        XBOND.mint(_shares, msg.sender);
    }

    function withdraw(uint256 _assets) public onlyVested {
        XBOND.withdraw(_assets, msg.sender, msg.sender);
    }

    function redeem(uint256 _shares) public onlyVested {
        XBOND.redeem(_shares, msg.sender, msg.sender);
    }

}
