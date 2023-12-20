// contracts/QuantLab.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./Ownable.sol";

contract QuantLab is ERC20, Ownable {

  address private destinationWallet = address(0x0000000000000);
  uint256 public tokenPrice = 0.0001 ether;

    constructor() ERC20("QuantLab", "QNTL") {
      
      uint256 initialSupply = 1000000000 * 10 ** decimals();
      _mint(msg.sender, initialSupply);
    }

    
    function sale(uint256 _amount) public payable {
      require(totalSupply() >= _amount, "Not enough tokens");

      require(msg.value >= _amount * tokenPrice, "Not enough ETH");
      _transfer(address(this), msg.sender, _amount);
      payable(destinationWallet).transfer(msg.value);
        
    }

    //set destination wallet
    function setDestinationWallet(address _destinationWallet) external onlyOwner {
      destinationWallet = _destinationWallet;
    }

    //withdraw ETH from contract
    function withdraw() external onlyOwner {
      payable(msg.sender).transfer(address(this).balance);
    }

    //withdraw tokens from contract
    function withdrawTokens(uint256 _amount) external onlyOwner {
      _transfer(address(this), msg.sender, _amount);
    }

    //set token price
    function setTokenPrice(uint256 _price) external onlyOwner {
      tokenPrice = _price;
    }

    
    function mint(uint256 _amount) external onlyOwner {
      _mint(msg.sender, _amount);
    }
    
    function burn(uint256 _amount) external onlyOwner {
      _burn(msg.sender, _amount);
    }

    //implement selfdestruct
    function destroy() external onlyOwner {
      selfdestruct(payable(msg.sender));
    }
}
