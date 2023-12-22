pragma solidity ^0.8.0;
//SPDX-License-Identifier: MIT

import "./Ownable.sol";
import "./IERC20.sol";

/** 
 * Tales of Elleria
*/
contract ElleriaShop is Ownable {

  uint256 private purchaseCounter;
  
  /**
   * Counts the number of 
   * withdraw transactions.
  */
  function purchaseCount() external view returns (uint256) {
    return purchaseCounter;
  }

   /**
   * Allows someone to buy an item from our inter-chain shop.
   */
  function Transact(uint256 _amountInWEI, address _erc20Addr, uint256 quantity, uint256 listingId) external {
    IERC20(_erc20Addr).transferFrom(msg.sender, address(this), _amountInWEI);
    emit ShopPurchase(msg.sender, _erc20Addr, quantity, _amountInWEI, listingId, ++purchaseCounter);
  }

  /**
    * Allows the owner to withdraw ERC20 tokens from this contract.
    */
  function withdrawERC20(address _erc20Addr, address _recipient) external onlyOwner {
    IERC20(_erc20Addr).transfer(_recipient, IERC20(_erc20Addr).balanceOf(address(this)));
  }

  // Events
  event ShopPurchase(address indexed sender, address indexed erc20Address, uint256 quantity, uint256 value, uint256 listingId, uint256 counter);
}
