// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ERC20.sol";

import "./IPoints.sol";
import "./IRoleManager.sol";

/**huntnft
 * @dev Points is the contract that hold hunt point of every account, can be only modified by its owner
 * @notice DO NOT SUPPORT L2 cross layer call.
 */
contract Points is ERC20, IPoints {
    bool canTransfer;
    IRoleManager public immutable override getRoleCenter;

    constructor(address roleManager) ERC20("hunt nft point", "HNP") {
        getRoleCenter = IRoleManager(roleManager);
    }

    /// @notice require msg.sender have "POINT_OPERATOR_ROLE" in role center
    modifier onlyOperator() {
        require(getRoleCenter.isPointOperator(msg.sender), "only point operator role permitted");
        _;
    }

    function decimals() public pure override returns (uint8) {
        return 0;
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        require(canTransfer, "paused");
        return ERC20.transfer(to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        require(canTransfer, "paused");
        return ERC20.transferFrom(from, to, amount);
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        require(canTransfer, "paused");
        return ERC20.approve(spender, amount);
    }

    function addPoint(address _recipient, uint64 _amount) public onlyOperator {
        require(!canTransfer, "OPENED");
        ERC20._mint(_recipient, _amount);
    }

    function consumePoint(address _owner, uint64 _amount) public onlyOperator {
        require(!canTransfer, "OPENED");
        ERC20._burn(_owner, _amount);
    }

    function enableTransfer(bool enabled) public onlyOperator {
        require(!canTransfer, "can't close transfer");
        canTransfer = enabled;
    }
}

