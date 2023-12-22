// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import {ERC20} from "./ERC20.sol";
import {ERC4626} from "./ERC4626.sol";
import "./Kernel.sol";

/// @notice StakedBarnBridgeToken is the ERC20 token that represents voting power in the network.
contract StakedBarnBridgeToken is Module, ERC4626 {
    /*//////////////////////////////////////////////////////////////
                            MODULE INTERFACE
    //////////////////////////////////////////////////////////////*/

    constructor(Kernel _kernel, ERC20 _bond)
        Module(_kernel)
        ERC4626(_bond, "StakedBOND", "XBOND")
    {}

    /// @inheritdoc Module
    function KEYCODE() public pure override returns (bytes5) {
        return "XBOND";
    }

    /// @inheritdoc Module
    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        return (1, 0);
    }

    /*//////////////////////////////////////////////////////////////
                               CORE LOGIC
    //////////////////////////////////////////////////////////////*/


    mapping(address => uint256) public lastActionTimestamp;
    mapping(address => uint256) public lastDepositTimestamp;

    function totalAssets() public view override returns (uint256) {
        return asset.balanceOf(address(this));
    }

    function deposit(uint256 _assets, address _receiver) public override permissioned returns (uint256) {
        lastDepositTimestamp[_receiver] = block.timestamp;
        return super.deposit(_assets, _receiver);
    }

    function mint(uint256 _shares, address _receiver) public override permissioned returns (uint256) {
        lastDepositTimestamp[_receiver] = block.timestamp;
        return super.mint(_shares, _receiver);
    }
    
    function withdraw(uint256 _assets, address _receiver, address _owner) public override permissioned returns (uint256) {
        return super.withdraw(_assets, _receiver, _owner);
    }

    function redeem(uint256 _shares, address _receiver, address _owner) public override permissioned returns (uint256) {
        return super.redeem(_shares, _receiver, _owner);
    }

    /// @notice Transfers are locked for this token.
    function transfer(address _to, uint256 _amount) public override permissioned returns (bool) {
        return super.transfer(_to, _amount);
    }

    /// @notice TransferFrom is only allowed by permissioned policies.
    function transferFrom(
        address _from,
        address _to,
        uint256 _amount
    ) public override permissioned returns (bool) {
        return super.transferFrom(_from, _to, _amount);
    }

    function resetActionTimestamp(address _wallet) public permissioned {
        lastActionTimestamp[_wallet] = block.timestamp;
    }

}
