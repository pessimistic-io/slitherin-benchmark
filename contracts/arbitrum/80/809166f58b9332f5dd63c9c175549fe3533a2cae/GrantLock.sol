// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.15;

import {ShareTokenBase} from "./ShareTokenBase.sol";

/// @notice Token vault for grants.
/// @author Dinari (https://github.com/dinaricrypto/dinari-contracts/blob/main/contracts/terms/GrantLock.sol)
contract GrantLock {
    error GrantLock__NotGrantContract(address account);
    error GrantLock__TransferFailed();
    error GrantLock__ActiveBalance();

    ShareTokenBase public token;
    address public grant;

    constructor(address _holder, ShareTokenBase _token) {
        token = _token;
        grant = msg.sender;

        _token.delegate(_holder);
    }

    modifier onlyGrantContract() {
        if (msg.sender != grant) revert GrantLock__NotGrantContract(msg.sender);
        _;
    }

    /// @dev To clawback tokens on grant cancellation
    function withdraw(address to, uint256 amount) public virtual onlyGrantContract {
        if (!token.transfer(to, amount)) revert GrantLock__TransferFailed();
    }

    /// @dev Clean up
    function destroy(address payable to) external onlyGrantContract {
        if (token.balanceOf(address(this)) > 0) revert GrantLock__ActiveBalance();

        selfdestruct(to);
    }
}

