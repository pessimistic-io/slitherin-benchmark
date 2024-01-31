// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./Ownable.sol";
import "./ERC20Votes.sol";
import "./ERC20.sol";
import "./draft-ERC20Permit.sol";

import "./ITokenLockup.sol";

contract BlurToken is ERC20Votes, Ownable {

    uint256 private constant INITIAL_SUPPLY = 3_000_000_000;

    address[] public lockups;

    constructor() ERC20Permit("Blur") ERC20("Blur", "BLUR") {
        _mint(msg.sender, INITIAL_SUPPLY * 10 ** 18);
    }

    /**
     * @notice Adds token lockup addresses
     * @param _lockups Lockup addresses to add
     */
    function addLockups(address[] calldata _lockups) external onlyOwner {
        uint256 lockupsLength = _lockups.length;
        for (uint256 i = 0; i < lockupsLength; i++) {
            lockups.push(_lockups[i]);
        }
    }

    /**
     * @notice Adds token lockup balance to ERC20Votes.getVotes value
     * @param account Address to get vote total of
     */
    function getVotes(address account) public view override returns (uint256) {
        return ERC20Votes.getVotes(account) + _getTokenLockupBalance(account);
    }

    /**
     * @notice Adds token lockup balance to ERC20Votes.getPastVotes value
     * @param account Address to get past vote total of
     */
    function getPastVotes(address account, uint256 blockNumber) public view override returns (uint256) {
        return ERC20Votes.getPastVotes(account, blockNumber) + _getTokenLockupBalance(account);
    }

    /**
     * @notice Overrides ERC20Votes.delegates getter to default to self
     * @param account Address to get delegate of
     */
    function delegates(address account) public view override returns (address) {
        address _delegate = ERC20Votes.delegates(account);
        if (_delegate == address(0)) {
          _delegate = account;
        }
        return _delegate;
    }

    /**
     * @notice Calculates the balance that is allocated to the account across the token lockups
     * @param account Address to get locked balance of
     */
    function _getTokenLockupBalance(address account) internal view returns (uint256) {
        uint256 balance;
        uint256 lockupsLength = lockups.length;
        for (uint256 i; i < lockupsLength; i++) {
            balance += ITokenLockup(lockups[i]).balanceOf(account);
        }
        return balance;
    }
}

