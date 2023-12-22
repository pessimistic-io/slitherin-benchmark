// SPDX-License-Identifier: MIT
pragma solidity =0.8.15;
import "./Vault.sol";

contract VaultTimeLock is Vault {

    // Mapping address => uint256
    // Unix time until receiver can withdraw from vault
    mapping(address => uint256) public lockedTime;
    
    // Duration of lock up period in seconds
    uint256 public immutable lockDuration;

    constructor(IERC20Metadata asset_, uint256 lockDuration_)
    Vault(
        asset_
    ) 
    {
        lockDuration = lockDuration_;
    }

    // Override _deposit function to require owner to be receiver
    // Set lock time on owner to block transfers until after lock period

    /**
     * @dev Deposit/mint common workflow.
     */
    function _deposit(
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares
    ) internal virtual override {
        lockedTime[receiver] = block.timestamp + lockDuration;
        return super._deposit(caller, receiver, assets, shares);
    }

    /**
     * @dev Withdraw/redeem common workflow.
     */
    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal virtual override {
        require(lockedTime[owner] < block.timestamp, "_withdraw: Locked time not passed");
        return super._withdraw(caller, receiver, owner, assets, shares);
    }

    // transfer/transferFrom common workflow.
    // Override _transfer function to require lock time to be passed
    // This is what prevents users bypassing withdrawals before lock period is over
    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        require(
            lockedTime[from] < block.timestamp,
            "_transfer: Locked time not passed"
        );
        return super._transfer(from, to, amount);
    }
}

