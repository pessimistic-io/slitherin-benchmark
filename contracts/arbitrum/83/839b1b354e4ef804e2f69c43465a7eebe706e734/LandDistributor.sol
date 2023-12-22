// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./interfaces_IERC777.sol";
import "./ERC777Holder.sol";
import "./Permissioned.sol";

contract LandDistributor is Permissioned, ERC777Holder {

    constructor(
        address landContractAddress
    ) {
        require(landContractAddress != address(0),"Contract can't be zero address");
        landContract = IERC777(landContractAddress);
    }

    /// @dev This is the Land contract
    IERC777 internal immutable landContract;

    /// @dev Issue Land to recipient
    /// @param recipient amount to send
    /// @param amount amount to add
    function issueLand(address recipient, uint256 amount)
        external
        onlyAllowed
    {
        // Send to the recipient
        IERC777(landContract).operatorSend(address(this), recipient, amount , "", "");
    }

    /// @dev Add an amount of a token to the contract
    /// @param amount amount to add
    function addLand(uint256 amount)
        external
        onlyOwner
    {
        // Send Land to the contract
        IERC777(landContract).operatorSend(_msgSender(), address(this), amount , "", "");
    }

    /// @dev Allows the owner to withdraw tokens from the contract
    function withdrawLand() 
        external 
        onlyOwner 
    {
        // Calculate the token balance
        uint256 contractBalance = IERC777(landContract).balanceOf(address(this));
        // Ensure the token balance greater than zero
        require(contractBalance > 0, "There's no balance to withdraw");
        // Withdraw the balance of Land from the contract
        IERC777(landContract).operatorSend(address(this), msg.sender, contractBalance, "", "");
    }

  function _tokensReceived(IERC777 token, uint256 amount, bytes memory) internal view override {
    require(amount > 0, "You must receive a positive number of tokens");
    require(_msgSender() == address(token),"Unexpected token sender");
    require(address(token) == address(landContract),"The contract can only recieve Land tokens");
  }

}

