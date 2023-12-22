// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.16;

import "./Ownable.sol";
import "./ERC20Burnable.sol";
/// @title  Token Distributor
/// @notice Holds tokens for users to claim.
/// @dev    Unlike a merkle distributor this contract uses storage to record claims rather than a
///         merkle root. This is because calldata on Arbitrum is relatively expensive when compared with
///         storage, since calldata uses L1 gas.
///         After construction do the following
///         1. transfer tokens to this contract
///         2. setRecipients - called as many times as required to set all the recipients
///         3. transferOwnership - the ownership of the contract should be transferred to a new owner (eg DAO) after all recipients have been set
contract TokenDistributor is Ownable {
    /// @notice Token to be distributed
    ERC20Burnable public immutable token;
    /// @notice amount of tokens that can be claimed by address
    mapping(address => uint256) public claimableTokens;
    /// @notice Total amount of tokens claimable by recipients of this contract
    uint256 public totalClaimable;
    /// @notice Block number at which claiming starts
    uint256 public claimPeriodStart;
    /// @notice Block number at which claiming ends
    uint256 public claimPeriodEnd;

    /// @notice recipient can claim this amount of tokens
    event CanClaim(address indexed recipient, uint256 amount);
    /// @notice recipient has claimed this amount of tokens
    event HasClaimed(address indexed recipient, uint256 amount);
    /// @notice Tokens withdrawn
    event Withdrawal(address indexed recipient, uint256 amount);
    /// @notice Tokens burn
    event BurnLeft(uint256 amount);

    constructor(
        ERC20Burnable _token
    ) Ownable() {
        require(address(_token) != address(0), "TokenDistributor: zero token address");
        token = _token;
    }

    /// @notice Burn unclaimed tokens
    /// @dev This may only to be called once
    function brunLeftTokens() public onlyOwner{
        require(block.timestamp > claimPeriodEnd, "TokenDistributor: Claim time is not finished");
        uint amount = token.balanceOf(address(this));
        token.burn(amount);
        emit BurnLeft(amount);
    }

    /// @notice Set the start time when you can claim tokens
    /// @dev This may only to be called once
    function setClaimPeriodStart(uint256 _claimPeriodStart) public onlyOwner {
        if(_claimPeriodStart > 0){
            require(_claimPeriodStart > block.timestamp, "TokenDistributor: start should be in the future");
        }else{
            _claimPeriodStart = block.timestamp;
        }
        claimPeriodStart = _claimPeriodStart;
        claimPeriodEnd = _claimPeriodStart + 31 days;
        require(claimPeriodEnd > claimPeriodStart, "TokenDistributor: start should be before end");
    }

    /// @notice Allows owner to set a list of recipients to receive tokens
    /// @dev This may need to be called many times to set the full list of recipients
    function setRecipients(address[] calldata _recipients, uint256[] calldata _claimableAmount)
        external
        onlyOwner
    {
        require(
            _recipients.length > 0 && _recipients.length == _claimableAmount.length, "TokenDistributor: invalid array length"
        );
        uint256 sum = totalClaimable;
        for (uint256 i = 0; i < _recipients.length; i++) {
            // sanity check that the address being set is consistent
            require(claimableTokens[_recipients[i]] == 0, "TokenDistributor: recipient already set");
            claimableTokens[_recipients[i]] = _claimableAmount[i];
            emit CanClaim(_recipients[i], _claimableAmount[i]);
            unchecked {
                sum += _claimableAmount[i];
            }
        }

        // sanity check that the current has been sufficiently allocated
        require(token.balanceOf(address(this)) >= sum, "TokenDistributor: not enough balance");
        totalClaimable = sum;
    }


    /// @notice Allows a recipient to claim their tokens
    /// @dev Can only be called during the claim period
    function claim() public {
        require(claimPeriodStart > 0, "TokenDistributor: claim not started");
        require(block.timestamp >= claimPeriodStart, "TokenDistributor: claim not started");
        require(block.timestamp < claimPeriodEnd, "TokenDistributor: claim ended");

        uint256 amount = claimableTokens[msg.sender];
        require(amount > 0, "TokenDistributor: nothing to claim");

        claimableTokens[msg.sender] = 0;

        // we don't use safeTransfer since impl is assumed to be OZ
        require(token.transfer(msg.sender, amount), "TokenDistributor: fail token transfer");
        emit HasClaimed(msg.sender, amount);
    }
}
